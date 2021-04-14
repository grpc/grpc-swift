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
import Dispatch
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOHTTP2

/// A connection pool for connections speaking gRPC over HTTP/2.
///
/// The connection pool offers callers with two ways of borrowing an `HTTP2StreamMultiplexer`. They
/// are:
///
///   1. Asking the pool for the multiplexer of any already available connection (that is, actively
///      connected to a remote peer and has capacity to create one more HTTP/2 stream without
///      exceeding 'SETTINGS_MAX_CONCURRENT_STREAMS'). The caller may also provide a preferred
///      `EventLoop`, if any available connection is running on that event loop then it will be used
///      in preference to other event loops. See `tryGetMultiplexer(preferredEventLoop:)` for more
///      details.
///   2. If no multiplexer is available immediately callers may choose to wait for one. The pool
///      will complete a promise to provide a multiplexer when one becomes available in the future.
///      Only a limited number of waiters are supported at any given time, beyond which requests for
///      a multiplexer will be rejected. This may be configured with `maximumConnectionWaiters`.
///      See `waitForMultiplexer(eventLoop:deadline:)` for more details.
///
/// The pool holds bookkeeping state for each connection. In order to maintain a balanced pool,
/// callers provided with a multiplexer must create exactly one HTTP/2 stream using it. As the
/// multiplexer resides in a `NIO.Channel` configured for gRPC the pool is automatically notified
/// when the stream is closed, making it available to another caller.
///
/// Beneath the covers, the pool holds a number of managed connections (as determined by
/// `maximumConnections`). Each connection is managed: reconnecting on failures with appropriate
/// backoff and closing the underlying channel when appropriate. As such the pool is mostly
/// responsible for bookkeeping (how many streams are available on each connection) and deciding
/// when another connection should be spun up (connections are all idle initially).
///
/// New connections are brought up in two cases: 1.) when more than `nextConnectionThreshold`
/// streams have been borrowed from a given connection, or 2.) when a waiter is enqueued. When
/// selecting a multiplexer for a caller, two properties are taken into consideration: the event
/// loop preference of the caller and the number of available streams on a connection. If an event
/// loop preference is given then the connection using that event loop with most available streams
/// is used, if no such connection exists or no preference is given then the connection with the
/// most available streams is used.
internal final class ConnectionPool {
  /// A lock which must be held when accessing any internal state. By convention all methods
  /// prefixed with an `_` assume the lock is held by the caller.
  private let lock = Lock()

  /// The HTTP/2 connections and their state.
  private var connections: ManagedHTTP2Connections

  /// Connection waiters. We limit the number of waiters to `maximumConnectionWaiters`, and waiters
  /// will wait at most `maximumConnectionWaitTime` before being failed (unless a more specific
  /// deadline is provided when enqueueing a waiter).
  private var connectionWaiters: CircularBuffer<Waiter>

  /// The maximum number of waiters at any given time. No additional waiters beyond this limit will
  /// be created and requests for a multiplexer will be failed.
  private let maximumConnectionWaiters: Int

  /// The default maximum amount of time a waiter will wait for before timing out and failing.
  private let maximumConnectionWaitTime: TimeAmount

  /// The maximum number of streams which may be borrowed from a connection before the pool requests
  /// that a new connection be brought up (assuming an idle connection exists to be brought up).
  private let nextConnectionThreshold: Int

  /// A channel provider used to create connections.
  private let channelProvider: DefaultChannelProvider

  /// A queue to execute the connectivity and HTTP/2 delegates on.
  private let delegateQueue: DispatchQueue

  /// A logger.
  private var logger: GRPCLogger

  /// The current state of the connection pool.
  private var state: State

  private enum State {
    /// The pool is running, callers may request a multiplexer from it.
    case active
    /// The pool is shutting down, requests for multiplexers will be failed. Underlying connections
    /// will be closed.
    case shuttingDown(EventLoopFuture<Void>)
    /// The pool is shutdown.
    case shutdown
  }

  internal init(
    target: ConnectionTarget,
    group: EventLoopGroup,
    maximumConnections: Int,
    maximumConnectionWaitTime: TimeAmount,
    maximumConnectionWaiters: Int,
    nextConnectionThreshold: Int,
    delegateQueue: DispatchQueue? = nil,
    logger: Logger
  ) {
    precondition(maximumConnections > 0)
    precondition(maximumConnectionWaiters >= 0)
    precondition(nextConnectionThreshold > 0)

    self.connections = ManagedHTTP2Connections(capacity: maximumConnections)

    // Avoid the first few reallocs.
    self.connectionWaiters = CircularBuffer(initialCapacity: 16)
    self.maximumConnectionWaitTime = maximumConnectionWaitTime
    self.maximumConnectionWaiters = maximumConnectionWaiters
    self.nextConnectionThreshold = nextConnectionThreshold

    // TODO: provide configuration.
    self.channelProvider = DefaultChannelProvider(
      connectionTarget: target,
      connectionKeepalive: ClientConnectionKeepalive(),
      connectionIdleTimeout: .minutes(5),
      tlsConfiguration: nil,
      tlsHostnameOverride: nil,
      tlsCustomVerificationCallback: nil,
      httpTargetWindowSize: 65535,
      errorDelegate: nil,
      debugChannelInitializer: nil
    )

    self.delegateQueue = DispatchQueue(label: "io.grpc.pool", target: delegateQueue)
    self.state = .active
    self.logger = GRPCLogger(wrapping: logger)

    self.logger[metadataKey: "pool.id"] = "\(ObjectIdentifier(self))"
    self.logger.debug("Setting up new connection pool", metadata: [
      "pool.size": "\(maximumConnections)",
      "pool.waiters.maxCount": "\(maximumConnectionWaiters)",
      "pool.waiters.maxWait": "\(maximumConnectionWaitTime)",
    ])

    // Fill the pool with managed connections (they'll be idle).
    for _ in 0 ..< maximumConnections {
      let (manager, id) = self.makeConnection(on: group.next())
      self._insertConnection(manager, withID: id)
    }
  }

  // MARK: - Connection Counts

  // Note: these are mostly only useful for testing.

  /// The number of connections in the pool in any state.
  internal var count: Int {
    return self.lock.withLock {
      return self.connections.count
    }
  }

  /// The number of idle connections in the pool.
  internal var idleCount: Int {
    return self.lock.withLock {
      return self.connections.idleCount
    }
  }

  /// The number of connections in the pool which may have streams available.
  internal var readyCount: Int {
    return self.lock.withLock {
      return self.connections.readyCount
    }
  }

  /// The number of connections in the pool which are actively connecting or backing off between
  /// connection attempts.
  internal var connectingCount: Int {
    return self.lock.withLock {
      return self.connections.connectingCount
    }
  }

  /// The total number of available HTTP/2 streams across all connections in the pool.
  internal var availableHTTP2Streams: Int {
    return self.lock.withLock {
      return self.connections.availableTokens
    }
  }

  /// The total number of borrowed HTTP/2 streams across all connections in the pool.
  internal var borrowedHTTP2Streams: Int {
    return self.lock.withLock {
      return self.connections.borrowedTokens
    }
  }

  // MARK: - Multiplexer

  /// Borrow a multiplexer from an existing connection in the pool if one is available.
  ///
  /// A multiplexer will be returned if there is a connection in the ready state which has spare
  /// capacity for creating a single HTTP/2 stream. If no connections have available streams then
  /// `nil` is returned.
  ///
  /// If a multiplexer is successfully borrowed from the pool the caller must use it to create
  /// exactly one HTTP/2 stream. The stream will be automatically returned to the pool when it is
  /// created.
  ///
  /// The caller may also specify a preferred `EventLoop` for the `Channel` in which the multiplexer
  /// resides. If no multiplexer is available with the preferred event loop then any available
  /// multiplexer will be returned. The `EventLoop` the of the `Channel` the multiplexer resides in
  /// is also returned to the caller.
  ///
  /// If this function returns `nil` because no connections are available, the caller may try
  /// calling `waitForMultiplexer(eventLoop:deadline:)` to be notified when a multiplexer becomes
  /// available.
  ///
  /// - Parameter preferredEventLoop: The preferred `EventLoop` that the `HTTP2StreamMultiplexer` is
  ///     using.
  /// - Returns: A tuple of the `HTTP2StreamMultiplexer` and the `EventLoop` the multiplexer is
  ///     using, or `nil` if no multiplexer is available.
  internal func tryGetMultiplexer(
    preferredEventLoop: EventLoop?
  ) -> (HTTP2StreamMultiplexer, EventLoop)? {
    return self.lock.withLock {
      return self._tryGetMultiplexer(preferredEventLoop: preferredEventLoop)
    }
  }

  /// Lock-held implementation of `tryGetMultiplexer(preferredEventLoop:)`.
  private func _tryGetMultiplexer(
    preferredEventLoop: EventLoop?
  ) -> (HTTP2StreamMultiplexer, EventLoop)? {
    guard case .active = self.state else {
      // Don't give out a multiplexer if we're shutting down or shutdown.
      return nil
    }

    let eventLoop: EventLoop
    let connectionID: ObjectIdentifier

    if let preferredEventLoop = preferredEventLoop,
      let id = self.connections.connectionIDWithMostAvailableTokens(on: preferredEventLoop) {
      eventLoop = preferredEventLoop
      connectionID = id
    } else if let id = self.connections.connectionIDWithMostAvailableTokens() {
      eventLoop = self.connections.eventLoopForConnection(withID: id)!
      connectionID = id
    } else {
      // No connections available.
      return nil
    }

    // Of all the usable connections, this one has the best token availability.
    let (multiplexer, borrowed) = self.connections.borrowTokenFromConnection(withID: connectionID)

    // If more tokens have been used on this connection then we should spin up another one.
    if borrowed >= self.nextConnectionThreshold {
      self._requestConnection()
    }

    self.logger.trace("Providing a multiplexer from available connection", metadata: [
      "pool.conn.id": "\(connectionID)",
    ])

    return (multiplexer, eventLoop)
  }

  /// Request a multiplexer for a single use when one becomes available in the future.
  ///
  /// - Parameters:
  ///   - eventLoop: The `EventLoop` to be notified about the multiplexer on. The multiplexer which
  ///       succeeds the returned `EventLoopFuture` may run on a different `EventLoop`.
  ///   - deadline: The deadline by which the returned `EventLoopFuture` will be failed if no
  ///       multiplexer has become available. If this is not provided then the deadline will be
  ///       `maximumConnectionWaitTime` from now.
  /// - Returns: A future `HTTP2StreamMultiplexer`.
  internal func waitForMultiplexer(
    eventLoop: EventLoop,
    until deadline: NIODeadline? = nil
  ) -> EventLoopFuture<HTTP2StreamMultiplexer> {
    let promise = eventLoop.makePromise(of: HTTP2StreamMultiplexer.self)
    let actualDeadline = deadline ?? .now() + self.maximumConnectionWaitTime

    self.lock.withLockVoid {
      self._waitForMultiplexer(promise: promise, until: actualDeadline)
    }

    return promise.futureResult
  }

  /// Lock-held implementation of `waitForMultiplexer(eventLoop:deadline:)`.
  private func _waitForMultiplexer(
    promise: EventLoopPromise<HTTP2StreamMultiplexer>,
    until deadline: NIODeadline
  ) {
    guard case .active = self.state else {
      // Shutdown or shutting down, not much we can do.
      promise.fail(ConnectionPoolError.shutdown)
      return
    }

    guard self.connectionWaiters.count < self.maximumConnectionWaiters else {
      // The connection waiter queue is full: avoid overwhelming the pool.
      promise.fail(ConnectionPoolError.tooManyWaiters)
      return
    }

    // Enqueue a waiter.
    let waiter = self.makeWaiter(promise: promise, deadline: deadline)
    self.connectionWaiters.append(waiter)

    // We're waiting for a multiplexer, chances are we don't have any capacity on existing ones,
    // request a connection.
    self._requestConnection()

    self.logger.trace("Enqueued connection waiter", metadata: [
      "pool.waiters.count": "\(self.connectionWaiters.count)",
    ])
  }

  /// Make a connection waiter, fulfilling the given promise with a multiplexer if one becomes
  /// available before the `deadline`.
  ///
  /// - Parameters:
  ///   - promise: The promise to complete when a multiplexer becomes available.
  ///   - deadline: The deadline to wait until before giving up on waiting for a multiplexer.
  /// - Returns: A `Waiter`.
  private func makeWaiter(
    promise: EventLoopPromise<HTTP2StreamMultiplexer>,
    deadline: NIODeadline
  ) -> Waiter {
    var waiter = Waiter(multiplexerPromise: promise)
    let waiterID = waiter.id

    // Schedule a timeout (executed on the event loop) to fail the promise.
    waiter.scheduleTimeout(at: deadline, on: promise.futureResult.eventLoop) {
      self.timeoutWaiter(withID: waiterID)
    }

    return waiter
  }

  /// Timeout and remove the waiter with the given `id`.
  /// - Parameter id: The `id` of the waiter which has timed out.
  private func timeoutWaiter(withID id: ObjectIdentifier) {
    self.lock.withLockVoid {
      self._timeoutWaiter(withID: id)
    }
  }

  /// Lock-held implementation of `timeoutWaiter(withID:)`.
  private func _timeoutWaiter(withID id: ObjectIdentifier) {
    if let index = self.connectionWaiters.firstIndex(where: { $0.id == id }) {
      let waiter = self.connectionWaiters.remove(at: index)
      waiter.fail(ConnectionPoolError.waiterTimedOut)
    }
  }

  /// Add a connection to the pool.
  ///
  /// - Parameter eventLoop: The `EventLoop` the connection should run on.
  /// - Returns: A tuple of the `ConnectionManager` and its `ObjectIdentifier`.
  private func makeConnection(on eventLoop: EventLoop) -> (ConnectionManager, ObjectIdentifier) {
    // TODO: configuration
    let manager = ConnectionManager(
      eventLoop: eventLoop,
      channelProvider: self.channelProvider,
      callStartBehavior: .waitsForConnectivity,
      connectionBackoff: ConnectionBackoff(),
      // This is set just below (we need the identifier).
      connectivityStateDelegate: nil,
      connectivityStateDelegateQueue: self.delegateQueue,
      logger: self.logger.unwrapped
    )

    let connectionManagerID = ObjectIdentifier(manager)

    // We hold the connection which holds the delegate which holds us. We break that cycle by
    // unsetting the delegates and removing connections when we shutdown.
    let delegate = Delegate(connectionID: connectionManagerID, pool: self)
    manager.monitor.delegate = delegate
    manager.monitor.http2Delegate = delegate

    return (manager, connectionManagerID)
  }

  /// Inserts a new connection manager into the pool.
  private func _insertConnection(_ manager: ConnectionManager, withID id: ObjectIdentifier) {
    self.connections.insertConnection(manager, withID: id)
    self.logger.trace("Connection added to pool", metadata: ["pool.conn.id": "\(id)"])
  }

  /// Request that an idle connection be started if one exists.
  private func _requestConnection() {
    if let id = self.connections.firstIdleConnectionID() {
      self._startConnection(withID: id)
    }
  }

  /// Start connecting the (idle) connection with the given `id`.
  ///
  /// - Parameter id: The `id` of the connection to start.
  private func _startConnection(withID id: ObjectIdentifier) {
    self.connections.startConnection(withID: id) { multiplexer in
      self.connectionIsReady(withID: id, multiplexer: multiplexer)
    }
  }

  /// Marks the connection with the given `id` as ready and to service any connection waiters.
  ///
  /// - Parameters:
  ///   - id: The `id` of the connection to mark as ready.
  ///   - multiplexer: The multiplexer for the connection with the given `id`.
  private func connectionIsReady(
    withID id: ObjectIdentifier,
    multiplexer: HTTP2StreamMultiplexer
  ) {
    self.lock.withLockVoid {
      self._connectionIsReady(withID: id, multiplexer: multiplexer)
    }
  }

  /// Lock-held implementation of `connectionIsReady(withID:multiplexer:)`.
  private func _connectionIsReady(
    withID id: ObjectIdentifier,
    multiplexer: HTTP2StreamMultiplexer
  ) {
    self.connections.connectionIsReady(withID: id, multiplexer: multiplexer)
    self._tryServiceManyWaiters()
  }

  /// Update the connectivity state of the connection with the given `id`.
  ///
  /// This should be called by the `Delegate` to notify the pool of changes to an underlying
  /// connection.
  ///
  /// - Parameters:
  ///   - state: The new connection state of the connection.
  ///   - id: The `id` of the connection which changed state.
  private func updateConnectivityState(
    _ state: ConnectivityState,
    forConnectionWithID id: ObjectIdentifier
  ) {
    self.lock.withLockVoid {
      self._updateConnectivityState(state, forConnectionWithID: id)
    }
  }

  /// Lock-held implementation of `updateConnectivityState(_:forConnectionWithID:)`.
  private func _updateConnectivityState(
    _ state: ConnectivityState,
    forConnectionWithID id: ObjectIdentifier
  ) {
    self.logger.trace("Pooled connection changed connectivity state", metadata: [
      "pool.conn.id": "\(id)",
      "pool.conn.state": "\(state)",
    ])

    if let action = self.connections.updateConnectivityState(state, forConnectionWithID: id) {
      switch action {
      case .nothing:
        ()

      case .startConnectingAgain:
        // The connection dropped: we need to ask the connection manager for another multiplexer so
        // that we don't hand out the from the dropped channel.
        self._startConnection(withID: id)

      case .removeFromConnectionList:
        // The connection is removed as a result of shutting down so we don't need to shut it down.
        if let manager = self.connections.removeConnection(withID: id) {
          manager.monitor.delegate = nil
          manager.monitor.http2Delegate = nil
        }
      }
    }
  }

  /// The connection with the given ID started quiescing. Remove it from the pool and replace it
  /// with a new idle connection on the same `EventLoop`.
  ///
  /// - Parameter id: The ID of the connection which is quiescing.
  private func connectionStartedQuiescing(withID id: ObjectIdentifier) {
    self.lock.withLockVoid {
      self._connectionStartedQuiescing(withID: id)
    }
  }

  // Lock-held implementation of `connectionStartedQuiescing(withID:)`.
  private func _connectionStartedQuiescing(withID id: ObjectIdentifier) {
    // The connection is quiescing, remove it and replace it with a new one on that same event
    // loop. We don't need to shut down the connection, it will do so once fully quiesced.
    if let manager = self.connections.removeConnection(withID: id) {
      // Unhook the delegates: we don't care about returned tokens or connectivity changes any more.
      manager.monitor.delegate = nil
      manager.monitor.http2Delegate = nil

      let (newManager, newID) = self.makeConnection(on: manager.eventLoop)
      self._insertConnection(newManager, withID: newID)
    }
  }

  /// Returns a token to the connection with the given `id` and attempts to service a connection
  /// waiter.
  ///
  /// - Parameter id: The ID of the connection to return a token for.
  private func returnTokenToConnection(withID id: ObjectIdentifier) {
    self.lock.withLockVoid {
      self._returnTokenToConnection(withID: id)
    }
  }

  /// Lock-held implementation of `returnTokenToConnection(withID:)`.
  private func _returnTokenToConnection(withID id: ObjectIdentifier) {
    self.logger.trace("Returning token to pooled connection", metadata: ["pool.conn.id": "\(id)"])
    self.connections.returnTokenToConnection(withID: id)
    self._tryServiceFirstWaiterUsingConnection(withID: id)
  }

  /// Update the maximum number of leases available to the connection with the given `id`.
  ///
  /// - Parameters:
  ///   - limit: The maximum number of tokens available on a connection at a given time.
  ///   - id: The ID of the connection to update.
  private func updateMaximumAvailableTokens(
    _ limit: Int,
    forConnectionWithID id: ObjectIdentifier
  ) {
    self.lock.withLockVoid {
      self._updateMaximumAvailableTokens(limit, forConnectionWithID: id)
    }
  }

  /// Lock-held implementation of `updateMaximumAvailableTokens(_:forConnectionWithID:)`.
  private func _updateMaximumAvailableTokens(
    _ limit: Int,
    forConnectionWithID id: ObjectIdentifier
  ) {
    let oldLimit = self.connections.updateMaximumAvailableTokens(limit, forConnectionWithID: id)

    if let oldLimit = oldLimit, limit > oldLimit {
      // The limit increased, we may be able to service some waiters.
      self._tryServiceManyWaiters()
    }
  }

  /// Try to provide a multiplexer to at most one waiter using the connection identified by `id`.
  private func _tryServiceFirstWaiterUsingConnection(withID id: ObjectIdentifier) {
    // No point trying if there are no waiters.
    if self.connectionWaiters.isEmpty {
      return
    }

    // Check this connection has available tokens.
    guard let tokens = self.connections.availableTokensForConnection(withID: id), tokens > 0 else {
      return
    }

    let (multiplexer, _) = self.connections.borrowTokenFromConnection(withID: id)
    let waiter = self.connectionWaiters.removeFirst()

    self.logger.trace("Providing a multiplexer to connection waiter", metadata: [
      "pool.waiters.count": "\(self.connectionWaiters.count)",
      "pool.waiter.id": "\(waiter.id)",
      "pool.conn.id": "\(id)",
    ])

    waiter.succeed(multiplexer)
  }

  /// Try to provide many waiters with multiplexers.
  private func _tryServiceManyWaiters() {
    // No point trying if there are no waiters.
    if self.connectionWaiters.isEmpty {
      return
    }

    self.logger.trace("Attempting to service many connection waiters", metadata: [
      "pool.waiters.count": "\(self.connectionWaiters.count)",
    ])

    // This could be smarter. Right now we could fully load connections rather than distributing
    // waiters across connections.
    while let leastLoadedID = self.connections.connectionIDWithMostAvailableTokens(),
      self.connectionWaiters.count > 0 {
      // Force unwrap is okay: the connection ID must exist.
      let available = self.connections.availableTokensForConnection(withID: leastLoadedID)!
      // Don't borrow more than is available or necessary.
      let tokensToBorrow = min(self.connectionWaiters.count, available)

      let (multiplexer, _) = self.connections.borrowTokens(
        tokensToBorrow,
        fromConnectionWithID: leastLoadedID
      )

      // Okay, now vend out the multiplexer to a bunch of waiters.
      for _ in 0 ..< tokensToBorrow {
        let waiter = self.connectionWaiters.removeFirst()
        self.logger.trace("Providing a multiplexer to connection waiter", metadata: [
          "pool.waiters.count": "\(self.connectionWaiters.count)",
          "pool.waiter.id": "\(waiter.id)",
          "pool.conn.id": "\(leastLoadedID)",
        ])
        waiter.succeed(multiplexer)
      }
    }
  }

  // MARK: - Shutdown

  /// Shutdown the connection pool, closing any active connections.
  ///
  /// - Note: This function is idempotent.
  /// - Parameter promise: An `EventLoopPromise` to complete once the pool has been shutdown.
  internal func shutdown(promise: EventLoopPromise<Void>) {
    self.lock.withLockVoid {
      self._shutdown(promise: promise)
    }
  }

  /// Lock-held implementation of `shutdown(promise:)`.
  private func _shutdown(promise: EventLoopPromise<Void>) {
    let eventLoop = promise.futureResult.eventLoop

    switch self.state {
    case .active:
      self.logger.debug("shutting down connection pool")

      // We're about to shut down.
      self.state = .shuttingDown(promise.futureResult)

      promise.futureResult.whenComplete { _ in
        self.shutdownCompleted()
      }

      // Remove all the managers and drop their delegates since they hold a reference to the pool.
      let connectionManagers = self.connections.removeAll()
      let shutdownFutures = connectionManagers.map { manager -> EventLoopFuture<Void> in
        manager.monitor.delegate = nil
        manager.monitor.http2Delegate = nil
        return manager.shutdown()
      }

      // TODO: use the 'promise' accepting version when it's released to save an allocation.
      EventLoopFuture.andAllSucceed(shutdownFutures, on: eventLoop).cascade(to: promise)

      // Fail and remove all the connection waiters.
      while let waiter = self.connectionWaiters.popFirst() {
        waiter.fail(ConnectionPoolError.shutdown)
      }

    case let .shuttingDown(future):
      promise.completeWith(future)

    case .shutdown:
      promise.succeed(())
    }
  }

  /// The shutdown has completed.
  private func shutdownCompleted() {
    self.lock.withLockVoid {
      self._shutdownCompleted()
    }
  }

  private func _shutdownCompleted() {
    switch self.state {
    case .shuttingDown:
      self.logger.debug("connection pool shutdown")
      self.state = .shutdown

    case .active, .shutdown:
      preconditionFailure()
    }
  }
}

extension ConnectionPool {
  /// A connectivity state delegate to inform the `ConnectionPool` about changes to the
  /// connectivity state of a given connection.
  internal final class Delegate: ConnectivityStateDelegate, HTTP2ConnectionDelegate {
    /// The ID of the connection this delegate is for.
    private let id: ObjectIdentifier

    /// The connection pool the connection resides in.
    private let pool: ConnectionPool

    internal init(connectionID id: ObjectIdentifier, pool: ConnectionPool) {
      self.id = id
      self.pool = pool
    }

    internal func connectivityStateDidChange(
      from oldState: ConnectivityState,
      to newState: ConnectivityState
    ) {
      self.pool.updateConnectivityState(newState, forConnectionWithID: self.id)
    }

    internal func connectionStartedQuiescing() {
      self.pool.connectionStartedQuiescing(withID: self.id)
    }

    internal func streamClosed() {
      self.pool.returnTokenToConnection(withID: self.id)
    }

    internal func maxConcurrentStreamsChanged(_ maxConcurrentStreams: Int) {
      self.pool.updateMaximumAvailableTokens(maxConcurrentStreams, forConnectionWithID: self.id)
    }
  }
}

extension ConnectionPool {
  internal struct Waiter {
    /// A promise for an HTTP/2 stream multiplexer.
    private let multiplexerPromise: EventLoopPromise<HTTP2StreamMultiplexer>

    /// A scheduled timeout task.
    private var timeout: Optional<Scheduled<Void>>

    /// An identifier for this waiter.
    internal var id: ObjectIdentifier {
      return ObjectIdentifier(self.multiplexerPromise.futureResult)
    }

    internal init(multiplexerPromise: EventLoopPromise<HTTP2StreamMultiplexer>) {
      self.multiplexerPromise = multiplexerPromise
      self.timeout = nil
    }

    /// Schedule a task to execute if the given deadline passes. The task will be cancelled if the
    /// the waiter is succeeded or failed before the deadline is reached.
    ///
    /// - Parameters:
    ///   - deadline: The point in time at which the callback will execute unless cancelled.
    ///   - eventLoop: The `EventLoop` to schedule the timeout task on.
    ///   - execute: A closure to execute when the timeout fires. It is executed on `eventLoop`.
    internal mutating func scheduleTimeout(
      at deadline: NIODeadline,
      on eventLoop: EventLoop,
      onTimeout execute: @escaping () -> Void
    ) {
      assert(self.timeout == nil)
      self.timeout = eventLoop.scheduleTask(deadline: deadline, execute)
    }

    /// Succeed the waiter with `multiplexer` and cancel any timeout task..
    internal func succeed(_ multiplexer: HTTP2StreamMultiplexer) {
      self.timeout?.cancel()
      self.multiplexerPromise.succeed(multiplexer)
    }

    /// Fail the waiter with `error` and cancel any timeout task.
    internal func fail(_ error: Error) {
      self.timeout?.cancel()
      self.multiplexerPromise.fail(error)
    }
  }
}

internal enum ConnectionPoolError: Error, Hashable, GRPCStatusTransformable {
  case shutdown
  case tooManyWaiters
  case waiterTimedOut

  internal func makeGRPCStatus() -> GRPCStatus {
    switch self {
    case .shutdown:
      return GRPCStatus(
        code: .unavailable,
        message: "The operation can't be performed because the connection pool is shutdown."
      )

    case .tooManyWaiters:
      return GRPCStatus(
        code: .unavailable,
        message: "The connection pool has reached the maximum number of waiters."
      )

    case .waiterTimedOut:
      return GRPCStatus(
        code: .unavailable,
        message: "Timed out waiting for an available connection."
      )
    }
  }
}
