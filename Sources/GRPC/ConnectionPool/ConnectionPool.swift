/*
 * Copyright 2021, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOHTTP2

internal final class ConnectionPool {
  /// The event loop all connections in this pool are running on.
  internal let eventLoop: EventLoop

  private enum State {
    case active
    case shuttingDown(EventLoopFuture<Void>)
    case shutdown
  }

  /// The state of the connection pool.
  private var state: State = .active

  /// Connection managers and their stream availability state keyed by the ID of the connection
  /// manager.
  ///
  /// Connections are accessed by their ID for connection state changes (infrequent) and when
  /// streams are closed (frequent). However when choosing which connection to succeed a waiter
  /// with (frequent) requires the connections to be ordered by their availability. A dictionary
  /// might not be the most efficient data structure (a queue prioritised by stream availability may
  /// be a better choice given the number of connections is likely to be very low in practice).
  private var connections: [ConnectionManagerID: PerConnectionState]

  /// The threshold which if exceeded when creating a stream determines whether the pool will
  /// start connecting an idle connection (if one exists).
  ///
  /// The 'load' is calculated as the ratio of demand for streams (the sum of the number of waiters
  /// and the number of reserved streams) and the total number of streams which non-idle connections
  /// could support (this includes the streams that a connection in the connecting state could
  /// support).
  private let reservationLoadThreshold: Double

  /// The assumed value for the maximum number of concurrent streams a connection can support. We
  /// assume a connection will support this many streams until we know better.
  private let assumedMaxConcurrentStreams: Int

  /// A queue of waiters which may or may not get a stream in the future.
  private var waiters: CircularBuffer<Waiter>

  /// The maximum number of waiters allowed, the size of `waiters` must not exceed this value. If
  /// there are this many waiters in the queue then the next waiter will be failed immediately.
  private let maxWaiters: Int

  /// Provides a channel factory to the `ConnectionManager`.
  private let channelProvider: ConnectionManagerChannelProvider

  /// The object to notify about changes to stream reservations; in practice this is usually
  /// the `PoolManager`.
  private let streamLender: StreamLender

  /// A logger which always sets "GRPC" as its source.
  private let logger: GRPCLogger

  /// Returns `NIODeadline` representing 'now'. This is useful for testing.
  private let now: () -> NIODeadline

  /// Logging metadata keys.
  private enum Metadata {
    /// The ID of this pool.
    static let id = "pool.id"
    /// The number of stream reservations (i.e. number of open streams + number of waiters).
    static let reservationsCount = "pool.reservations.count"
    /// The number of streams this pool can support with non-idle connections at this time.
    static let reservationsCapacity = "pool.reservations.capacity"
    /// The current reservation load (i.e. reservation count / reservation capacity)
    static let reservationsLoad = "pool.reservations.load"
    /// The reservation load threshold, above which a new connection will be created (if possible).
    static let reservationsLoadThreshold = "pool.reservations.loadThreshold"
    /// The current number of waiters in the pool.
    static let waitersCount = "pool.waiters.count"
    /// The maximum number of waiters the pool is configured to allow.
    static let waitersMax = "pool.waiters.max"
    /// The number of waiters which were successfully serviced.
    static let waitersServiced = "pool.waiters.serviced"
    /// The ID of waiter.
    static let waiterID = "pool.waiter.id"
  }

  init(
    eventLoop: EventLoop,
    maxWaiters: Int,
    reservationLoadThreshold: Double,
    assumedMaxConcurrentStreams: Int,
    channelProvider: ConnectionManagerChannelProvider,
    streamLender: StreamLender,
    logger: GRPCLogger,
    now: @escaping () -> NIODeadline = NIODeadline.now
  ) {
    precondition(
      (0.0 ... 1.0).contains(reservationLoadThreshold),
      "reservationLoadThreshold must be within the range 0.0 ... 1.0"
    )
    self.reservationLoadThreshold = reservationLoadThreshold
    self.assumedMaxConcurrentStreams = assumedMaxConcurrentStreams

    self.connections = [:]
    self.maxWaiters = maxWaiters
    self.waiters = CircularBuffer(initialCapacity: 16)

    self.eventLoop = eventLoop
    self.channelProvider = channelProvider
    self.streamLender = streamLender
    self.logger = logger
    self.now = now
  }

  /// Initialize the connection pool.
  ///
  /// - Parameter connections: The number of connections to add to the pool.
  internal func initialize(connections: Int) {
    assert(self.connections.isEmpty)
    self.connections.reserveCapacity(connections)
    while self.connections.count < connections {
      self.addConnectionToPool()
    }
  }

  /// Make and add a new connection to the pool.
  private func addConnectionToPool() {
    let manager = ConnectionManager(
      eventLoop: self.eventLoop,
      channelProvider: self.channelProvider,
      callStartBehavior: .waitsForConnectivity,
      connectionBackoff: ConnectionBackoff(),
      connectivityDelegate: self,
      http2Delegate: self,
      logger: self.logger.unwrapped
    )
    self.connections[manager.id] = PerConnectionState(manager: manager)
  }

  // MARK: - Called from the pool manager

  /// Make and initialize an HTTP/2 stream `Channel`.
  ///
  /// - Parameters:
  ///   - deadline: The point in time by which the `promise` must have been resolved.
  ///   - promise: A promise for a `Channel`.
  ///   - logger: A request logger.
  ///   - initializer: A closure to initialize the `Channel` with.
  internal func makeStream(
    deadline: NIODeadline,
    promise: EventLoopPromise<Channel>,
    logger: GRPCLogger,
    initializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) {
    if self.eventLoop.inEventLoop {
      self._makeStream(
        deadline: deadline,
        promise: promise,
        logger: logger,
        initializer: initializer
      )
    } else {
      self.eventLoop.execute {
        self._makeStream(
          deadline: deadline,
          promise: promise,
          logger: logger,
          initializer: initializer
        )
      }
    }
  }

  /// See `makeStream(deadline:promise:logger:initializer:)`.
  internal func makeStream(
    deadline: NIODeadline,
    logger: GRPCLogger,
    initializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) -> EventLoopFuture<Channel> {
    let promise = self.eventLoop.makePromise(of: Channel.self)
    self.makeStream(deadline: deadline, promise: promise, logger: logger, initializer: initializer)
    return promise.futureResult
  }

  /// Shutdown the connection pool.
  ///
  /// Existing waiters will be failed and all underlying connections will be shutdown. Subsequent
  /// calls to `makeStream` will be failed immediately.
  internal func shutdown() -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)

    if self.eventLoop.inEventLoop {
      self._shutdown(promise: promise)
    } else {
      self.eventLoop.execute {
        self._shutdown(promise: promise)
      }
    }

    return promise.futureResult
  }

  /// See `makeStream(deadline:promise:logger:initializer:)`.
  ///
  /// - Important: Must be called on the pool's `EventLoop`.
  private func _makeStream(
    deadline: NIODeadline,
    promise: EventLoopPromise<Channel>,
    logger: GRPCLogger,
    initializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) {
    self.eventLoop.assertInEventLoop()

    guard case .active = self.state else {
      // Fail the promise right away if we're shutting down or already shut down.
      promise.fail(ConnectionPoolError.shutdown)
      return
    }

    // Try to make a stream on an existing connection.
    let streamCreated = self.tryMakeStream(promise: promise, initializer: initializer)

    if !streamCreated {
      // No stream was created, wait for one.
      self.enqueueWaiter(
        deadline: deadline,
        promise: promise,
        logger: logger,
        initializer: initializer
      )
    }
  }

  /// Try to find an existing connection on which we can make a stream.
  ///
  /// - Parameters:
  ///   - promise: A promise to succeed if we can make a stream.
  ///   - initializer: A closure to initialize the stream with.
  /// - Returns: A boolean value indicating whether the stream was created or not.
  private func tryMakeStream(
    promise: EventLoopPromise<Channel>,
    initializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) -> Bool {
    // We shouldn't jump the queue.
    guard self.waiters.isEmpty else {
      return false
    }

    // Reserve a stream, if we can.
    guard let multiplexer = self.reserveStreamFromMostAvailableConnection() else {
      return false
    }

    multiplexer.createStreamChannel(promise: promise, initializer)

    // Has reserving another stream tipped us over the limit for needing another connection?
    if self.shouldBringUpAnotherConnection() {
      self.startConnectingIdleConnection()
    }

    return true
  }

  /// Enqueue a waiter to be provided with a stream at some point in the future.
  ///
  /// - Parameters:
  ///   - deadline: The point in time by which the promise should have been completed.
  ///   - promise: The promise to complete with the `Channel`.
  ///   - logger: A logger.
  ///   - initializer: A closure to initialize the `Channel` with.
  private func enqueueWaiter(
    deadline: NIODeadline,
    promise: EventLoopPromise<Channel>,
    logger: GRPCLogger,
    initializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) {
    // Don't overwhelm the pool with too many waiters.
    guard self.waiters.count < self.maxWaiters else {
      logger.trace("connection pool has too many waiters", metadata: [
        Metadata.waitersMax: "\(self.maxWaiters)",
      ])
      promise.fail(ConnectionPoolError.tooManyWaiters)
      return
    }

    let waiter = Waiter(deadline: deadline, promise: promise, channelInitializer: initializer)

    // Fail the waiter and punt it from the queue when it times out. It's okay that we schedule the
    // timeout before appending it to the waiters, it wont run until the next event loop tick at the
    // earliest (even if the deadline has already passed).
    waiter.scheduleTimeout(on: self.eventLoop) {
      waiter.fail(ConnectionPoolError.deadlineExceeded)
      if let index = self.waiters.firstIndex(where: { $0.id == waiter.id }) {
        self.waiters.remove(at: index)

        logger.trace("timed out waiting for a connection", metadata: [
          Metadata.waiterID: "\(waiter.id)",
          Metadata.waitersCount: "\(self.waiters.count)",
        ])
      }
    }

    // request logger
    logger.debug("waiting for a connection to become available", metadata: [
      Metadata.waiterID: "\(waiter.id)",
      Metadata.waitersCount: "\(self.waiters.count)",
    ])

    self.waiters.append(waiter)

    // pool logger
    self.logger.trace("enqueued connection waiter", metadata: [
      Metadata.waitersCount: "\(self.waiters.count)",
    ])

    if self.shouldBringUpAnotherConnection() {
      self.startConnectingIdleConnection()
    }
  }

  /// Compute the current demand and capacity for streams.
  ///
  /// The 'demand' for streams is the number of reserved streams and the number of waiters. The
  /// capacity for streams is the product of max concurrent streams and the number of non-idle
  /// connections.
  ///
  /// - Returns: A tuple of the demand and capacity for streams.
  private func computeStreamDemandAndCapacity() -> (demand: Int, capacity: Int) {
    let demand = self.sync.reservedStreams + self.sync.waiters

    // TODO: make this cheaper by storing and incrementally updating the number of idle connections
    let capacity = self.connections.values.reduce(0) { sum, state in
      if state.manager.sync.isIdle {
        // Idle connection, no capacity.
        return sum
      } else if let knownMaxAvailableStreams = state.maxAvailableStreams {
        // A known value of max concurrent streams, i.e. the connection is active.
        return sum + knownMaxAvailableStreams
      } else {
        // Not idle and no known value, the connection must be connecting so use our assumed value.
        return sum + self.assumedMaxConcurrentStreams
      }
    }

    return (demand, capacity)
  }

  /// Returns whether the pool should start connecting an idle connection (if one exists).
  private func shouldBringUpAnotherConnection() -> Bool {
    let (demand, capacity) = self.computeStreamDemandAndCapacity()

    // Infinite -- i.e. all connections are idle or no connections exist -- is okay here as it
    // will always be greater than the threshold and a new connection will be spun up.
    let load = Double(demand) / Double(capacity)
    let loadExceedsThreshold = load >= self.reservationLoadThreshold

    if loadExceedsThreshold {
      self.logger.debug(
        "stream reservation load factor greater than or equal to threshold, bringing up additional connection if available",
        metadata: [
          Metadata.reservationsCount: "\(demand)",
          Metadata.reservationsCapacity: "\(capacity)",
          Metadata.reservationsLoad: "\(load)",
          Metadata.reservationsLoadThreshold: "\(self.reservationLoadThreshold)",
        ]
      )
    }

    return loadExceedsThreshold
  }

  /// Starts connecting an idle connection, if one exists.
  private func startConnectingIdleConnection() {
    if let index = self.connections.values.firstIndex(where: { $0.manager.sync.isIdle }) {
      self.connections.values[index].manager.sync.startConnecting()
    }
  }

  /// Returns the index in `self.connections.values` of the connection with the most available
  /// streams. Returns `self.connections.endIndex` if no connection has at least one stream
  /// available.
  ///
  /// - Note: this is linear in the number of connections.
  private func mostAvailableConnectionIndex(
  ) -> Dictionary<ConnectionManagerID, PerConnectionState>.Index {
    var index = self.connections.values.startIndex
    var selectedIndex = self.connections.values.endIndex
    var mostAvailableStreams = 0

    while index != self.connections.values.endIndex {
      let availableStreams = self.connections.values[index].availableStreams
      if availableStreams > mostAvailableStreams {
        mostAvailableStreams = availableStreams
        selectedIndex = index
      }

      self.connections.values.formIndex(after: &index)
    }

    return selectedIndex
  }

  /// Reserves a stream from the connection with the most available streams, if one exists.
  ///
  /// - Returns: The `HTTP2StreamMultiplexer` from the connection the stream was reserved from,
  ///     or `nil` if no stream could be reserved.
  private func reserveStreamFromMostAvailableConnection() -> HTTP2StreamMultiplexer? {
    let index = self.mostAvailableConnectionIndex()

    if index != self.connections.endIndex {
      // '!' is okay here; the most available connection must have at least one stream available
      // to reserve.
      return self.connections.values[index].reserveStream()!
    } else {
      return nil
    }
  }

  /// See `shutdown()`.
  ///
  /// - Parameter promise: A `promise` to complete when the pool has been shutdown.
  private func _shutdown(promise: EventLoopPromise<Void>) {
    self.eventLoop.assertInEventLoop()

    switch self.state {
    case .active:
      self.logger.debug("shutting down connection pool")

      // We're shutting down now and when that's done we'll be fully shutdown.
      self.state = .shuttingDown(promise.futureResult)
      promise.futureResult.whenComplete { _ in
        self.state = .shutdown
        self.logger.trace("finished shutting down connection pool")
      }

      // Shutdown all the connections and remove them from the pool.
      let allShutdown: [EventLoopFuture<Void>] = self.connections.values.map {
        return $0.manager.shutdown()
      }
      self.connections.removeAll()

      // Fail the outstanding waiters.
      while let waiter = self.waiters.popFirst() {
        waiter.fail(ConnectionPoolError.shutdown)
      }

      // Cascade the result of the shutdown into the promise.
      EventLoopFuture.andAllSucceed(allShutdown, promise: promise)

    case let .shuttingDown(future):
      // We're already shutting down, cascade the result.
      promise.completeWith(future)

    case .shutdown:
      // Already shutdown, fine.
      promise.succeed(())
    }
  }
}

extension ConnectionPool: ConnectionManagerConnectivityDelegate {
  func connectionStateDidChange(
    _ manager: ConnectionManager,
    from oldState: ConnectivityState,
    to newState: ConnectivityState
  ) {
    switch (oldState, newState) {
    case (.ready, .transientFailure),
         (.ready, .idle),
         (.ready, .shutdown):
      // The connection is no longer available.
      self.connectionUnavailable(manager.id)

    default:
      // We're only interested in connection drops.
      ()
    }
  }

  func connectionIsQuiescing(_ manager: ConnectionManager) {
    self.eventLoop.assertInEventLoop()
    guard let removed = self.connections.removeValue(forKey: manager.id) else {
      return
    }

    // Drop any delegates. We're no longer interested in these events.
    removed.manager.sync.connectivityDelegate = nil
    removed.manager.sync.http2Delegate = nil

    // Replace the connection with a new idle one.
    self.addConnectionToPool()

    // Since we're removing this connection from the pool, the pool manager can ignore any streams
    // reserved against this connection.
    //
    // Note: we don't need to adjust the number of available streams as the number of connections
    // hasn't changed.
    self.streamLender.returnStreams(removed.reservedStreams, to: self)
  }

  /// A connection has become unavailable.
  private func connectionUnavailable(_ id: ConnectionManagerID) {
    self.eventLoop.assertInEventLoop()
    // The connection is no longer available: any streams which haven't been closed will be counted
    // as a dropped reservation, we need to tell the pool manager about them.
    if let droppedReservations = self.connections[id]?.unavailable(), droppedReservations > 0 {
      self.streamLender.returnStreams(droppedReservations, to: self)
    }
  }
}

extension ConnectionPool: ConnectionManagerHTTP2Delegate {
  internal func streamClosed(_ manager: ConnectionManager) {
    self.eventLoop.assertInEventLoop()

    // Return the stream the connection and to the pool manager.
    self.connections[manager.id]?.returnStream()
    self.streamLender.returnStreams(1, to: self)

    // A stream was returned: we may be able to service a waiter now.
    self.tryServiceWaiters()
  }

  internal func receivedSettingsMaxConcurrentStreams(
    _ manager: ConnectionManager,
    maxConcurrentStreams: Int
  ) {
    self.eventLoop.assertInEventLoop()

    let previous = self.connections[manager.id]?.updateMaxConcurrentStreams(maxConcurrentStreams)
    let delta: Int

    if let previousValue = previous {
      // There was a previous value of max concurrent streams, i.e. a change in value for an
      // existing connection.
      delta = maxConcurrentStreams - previousValue
    } else {
      // There was no previous value so this must be a new connection. We'll compare against our
      // assumed default.
      delta = maxConcurrentStreams - self.assumedMaxConcurrentStreams
    }

    if delta != 0 {
      self.streamLender.changeStreamCapacity(by: delta, for: self)
    }

    // We always check, even if `delta` isn't greater than zero as this might be a new connection.
    self.tryServiceWaiters()
  }
}

extension ConnectionPool {
  // MARK: - Waiters

  /// Try to service as many waiters as possible.
  ///
  /// This an expensive operation, in the worst case it will be `O(W ⨉ N)` where `W` is the number
  /// of waiters and `N` is the number of connections.
  private func tryServiceWaiters() {
    if self.waiters.isEmpty { return }

    self.logger.trace("servicing waiters", metadata: [
      Metadata.waitersCount: "\(self.waiters.count)",
    ])

    let now = self.now()
    var serviced = 0

    while !self.waiters.isEmpty {
      if self.waiters.first!.deadlineIsAfter(now) {
        if let multiplexer = self.reserveStreamFromMostAvailableConnection() {
          // The waiter's deadline is in the future, and we have a suitable connection. Remove and
          // succeed the waiter.
          let waiter = self.waiters.removeFirst()
          serviced &+= 1
          waiter.succeed(with: multiplexer)
        } else {
          // There are waiters but no available connections, we're done.
          break
        }
      } else {
        // The waiter's deadline has already expired, there's no point completing it. Remove it and
        // let its scheduled timeout fail the promise.
        self.waiters.removeFirst()
      }
    }

    self.logger.trace("done servicing waiters", metadata: [
      Metadata.waitersCount: "\(self.waiters.count)",
      Metadata.waitersServiced: "\(serviced)",
    ])
  }
}

extension ConnectionPool {
  /// Synchronous operations for the pool, mostly used by tests.
  internal struct Sync {
    private let pool: ConnectionPool

    fileprivate init(_ pool: ConnectionPool) {
      self.pool = pool
    }

    /// The number of outstanding connection waiters.
    internal var waiters: Int {
      self.pool.eventLoop.assertInEventLoop()
      return self.pool.waiters.count
    }

    /// The number of connection currently in the pool (in any state).
    internal var connections: Int {
      self.pool.eventLoop.assertInEventLoop()
      return self.pool.connections.count
    }

    /// The number of idle connections in the pool.
    internal var idleConnections: Int {
      self.pool.eventLoop.assertInEventLoop()
      return self.pool.connections.values.reduce(0) { $0 &+ ($1.manager.sync.isIdle ? 1 : 0) }
    }

    /// The number of streams currently available to reserve across all connections in the pool.
    internal var availableStreams: Int {
      self.pool.eventLoop.assertInEventLoop()
      return self.pool.connections.values.reduce(0) { $0 + $1.availableStreams }
    }

    /// The number of streams which have been reserved across all connections in the pool.
    internal var reservedStreams: Int {
      self.pool.eventLoop.assertInEventLoop()
      return self.pool.connections.values.reduce(0) { $0 + $1.reservedStreams }
    }
  }

  internal var sync: Sync {
    return Sync(self)
  }
}

internal enum ConnectionPoolError: Error {
  /// The pool is shutdown or shutting down.
  case shutdown

  /// There are too many waiters in the pool.
  case tooManyWaiters

  /// The deadline for creating a stream has passed.
  case deadlineExceeded
}
