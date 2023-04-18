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
import NIOConcurrencyHelpers
import NIOCore

// Unchecked because all mutable state is protected by a lock.
extension PooledChannel: @unchecked Sendable {}

@usableFromInline
internal final class PoolManager {
  /// Configuration used for each connection pool.
  @usableFromInline
  internal struct PerPoolConfiguration {
    /// The maximum number of connections per pool.
    @usableFromInline
    var maxConnections: Int

    /// The maximum number of waiters per pool.
    @usableFromInline
    var maxWaiters: Int

    /// A load threshold in the range `0.0 ... 1.0` beyond which another connection will be started
    /// (assuming there is a connection available to start).
    @usableFromInline
    var loadThreshold: Double

    /// The assumed value of HTTP/2 'SETTINGS_MAX_CONCURRENT_STREAMS'.
    @usableFromInline
    var assumedMaxConcurrentStreams: Int

    /// The assumed maximum number of streams concurrently available in the pool.
    @usableFromInline
    var assumedStreamCapacity: Int {
      return self.maxConnections * self.assumedMaxConcurrentStreams
    }

    @usableFromInline
    var connectionBackoff: ConnectionBackoff

    /// A `Channel` provider.
    @usableFromInline
    var channelProvider: DefaultChannelProvider

    @usableFromInline
    var delegate: GRPCConnectionPoolDelegate?

    @usableFromInline
    internal init(
      maxConnections: Int,
      maxWaiters: Int,
      loadThreshold: Double,
      assumedMaxConcurrentStreams: Int = 100,
      connectionBackoff: ConnectionBackoff,
      channelProvider: DefaultChannelProvider,
      delegate: GRPCConnectionPoolDelegate?
    ) {
      self.maxConnections = maxConnections
      self.maxWaiters = maxWaiters
      self.loadThreshold = loadThreshold
      self.assumedMaxConcurrentStreams = assumedMaxConcurrentStreams
      self.connectionBackoff = connectionBackoff
      self.channelProvider = channelProvider
      self.delegate = delegate
    }
  }

  /// Logging metadata keys
  private enum Metadata {
    /// The ID of the pool manager.
    static let id = "poolmanager.id"
    /// The number of managed connection pools.
    static let poolCount = "poolmanager.pools.count"
    /// The maximum number of connections per pool.
    static let connectionsPerPool = "poolmanager.pools.conns_per_pool"
    /// The maximum number of waiters per pool.
    static let waitersPerPool = "poolmanager.pools.waiters_per_pool"
  }

  /// The current state of the pool manager, `lock` must be held when accessing or
  /// modifying `state`.
  @usableFromInline
  internal var _state: PoolManagerStateMachine

  @usableFromInline
  internal var _pools: [ConnectionPool]

  @usableFromInline
  internal let lock = NIOLock()

  /// The `EventLoopGroup` providing `EventLoop`s for connection pools. Once initialized the manager
  /// will hold as many pools as there are loops in this `EventLoopGroup`.
  @usableFromInline
  internal let group: EventLoopGroup

  /// Make a new pool manager and initialize it.
  ///
  /// The pool manager manages one connection pool per event loop in the provided `EventLoopGroup`.
  /// Each connection pool is configured using the `perPoolConfiguration`.
  ///
  /// - Parameters:
  ///   - group: The `EventLoopGroup` providing `EventLoop`s to connections managed by the pool
  ///       manager.
  ///   - perPoolConfiguration: Configuration used by each connection pool managed by the manager.
  ///   - logger: A logger.
  /// - Returns: An initialized pool manager.
  @usableFromInline
  internal static func makeInitializedPoolManager(
    using group: EventLoopGroup,
    perPoolConfiguration: PerPoolConfiguration,
    logger: GRPCLogger
  ) -> PoolManager {
    let manager = PoolManager(privateButUsableFromInline_group: group)
    manager.initialize(perPoolConfiguration: perPoolConfiguration, logger: logger)
    return manager
  }

  @usableFromInline
  internal init(privateButUsableFromInline_group group: EventLoopGroup) {
    self._state = PoolManagerStateMachine(.inactive)
    self._pools = []
    self.group = group

    // The pool relies on the identity of each `EventLoop` in the `EventLoopGroup` being unique. In
    // practice this is unlikely to happen unless a custom `EventLoopGroup` is constructed, because
    // of that we'll only check when running in debug mode.
    debugOnly {
      let eventLoopIDs = group.makeIterator().map { ObjectIdentifier($0) }
      let uniqueEventLoopIDs = Set(eventLoopIDs)
      assert(
        eventLoopIDs.count == uniqueEventLoopIDs.count,
        "'group' contains non-unique event loops"
      )
    }
  }

  deinit {
    self.lock.withLock {
      assert(
        self._state.isShutdownOrShuttingDown,
        "The pool manager (\(ObjectIdentifier(self))) must be shutdown before going out of scope."
      )
    }
  }

  /// Initialize the pool manager, create and initialize one connection pool per event loop in the
  /// pools `EventLoopGroup`.
  ///
  /// - Important: Must only be called once.
  /// - Parameters:
  ///   - configuration: The configuration used for each connection pool.
  ///   - logger: A logger.
  private func initialize(
    perPoolConfiguration configuration: PerPoolConfiguration,
    logger: GRPCLogger
  ) {
    var logger = logger
    logger[metadataKey: Metadata.id] = "\(ObjectIdentifier(self))"

    let pools = self.makePools(perPoolConfiguration: configuration, logger: logger)

    logger.debug("initializing connection pool manager", metadata: [
      Metadata.poolCount: "\(pools.count)",
      Metadata.connectionsPerPool: "\(configuration.maxConnections)",
      Metadata.waitersPerPool: "\(configuration.maxWaiters)",
    ])

    // The assumed maximum number of streams concurrently available in each pool.
    let assumedCapacity = configuration.assumedStreamCapacity

    // The state machine stores the per-pool state keyed by the pools `EventLoopID` and tells the
    // pool manager about which pool to use/operate via the pools index in `self.pools`.
    let poolKeys = pools.indices.map { index in
      return ConnectionPoolKey(
        index: ConnectionPoolIndex(index),
        eventLoopID: pools[index].eventLoop.id
      )
    }

    self.lock.withLock {
      assert(self._pools.isEmpty)
      self._pools = pools

      // We'll blow up if we've already been initialized, that's fine, we don't allow callers to
      // call `initialize` directly.
      self._state.activatePools(keyedBy: poolKeys, assumingPerPoolCapacity: assumedCapacity)
    }

    for pool in pools {
      pool.initialize(connections: configuration.maxConnections)
    }
  }

  /// Make one pool per `EventLoop` in the pool's `EventLoopGroup`.
  /// - Parameters:
  ///   - configuration: The configuration to make each pool with.
  ///   - logger: A logger.
  /// - Returns: An array of `ConnectionPool`s.
  private func makePools(
    perPoolConfiguration configuration: PerPoolConfiguration,
    logger: GRPCLogger
  ) -> [ConnectionPool] {
    let eventLoops = self.group.makeIterator()
    return eventLoops.map { eventLoop in
      // We're creating a retain cycle here as each pool will reference the manager and the per-pool
      // state will hold the pool which will in turn be held by the pool manager. That's okay: when
      // the pool is shutdown the per-pool state and in turn each connection pool will be dropped.
      // and we'll break the cycle.
      return ConnectionPool(
        eventLoop: eventLoop,
        maxWaiters: configuration.maxWaiters,
        reservationLoadThreshold: configuration.loadThreshold,
        assumedMaxConcurrentStreams: configuration.assumedMaxConcurrentStreams,
        connectionBackoff: configuration.connectionBackoff,
        channelProvider: configuration.channelProvider,
        streamLender: self,
        delegate: configuration.delegate,
        logger: logger
      )
    }
  }

  // MARK: Stream Creation

  /// A future for a `Channel` from a managed connection pool. The `eventLoop` indicates the loop
  /// that the `Channel` is running on and therefore which event loop the RPC will use for its
  /// transport.
  @usableFromInline
  internal struct PooledStreamChannel {
    @inlinable
    internal init(futureResult: EventLoopFuture<Channel>) {
      self.futureResult = futureResult
    }

    /// The future `Channel`.
    @usableFromInline
    var futureResult: EventLoopFuture<Channel>

    /// The `EventLoop` that the `Channel` is using.
    @usableFromInline
    var eventLoop: EventLoop {
      return self.futureResult.eventLoop
    }
  }

  /// Make a stream and initialize it.
  ///
  /// - Parameters:
  ///   - preferredEventLoop: The `EventLoop` that the stream should be created on, if possible. If
  ///       a pool exists running this `EventLoop` then it will be chosen over all other pools,
  ///       irregardless of the load on the pool. If no pool exists on the preferred `EventLoop` or
  ///       no preference is given then the pool with the most streams available will be selected.
  ///       The `EventLoop` of the selected pool will be the same as the `EventLoop` of
  ///       the `EventLoopFuture<Channel>` returned from this call.
  ///   - deadline: The point in time by which the stream must have been selected. If this deadline
  ///       is passed then the returned `EventLoopFuture` will be failed.
  ///   - logger: A logger.
  ///   - initializer: A closure to initialize the `Channel` with.
  /// - Returns: A `PoolStreamChannel` indicating the future channel and `EventLoop` as that the
  ///     `Channel` is using. The future will be failed if the pool manager has been shutdown,
  ///     the deadline has passed before a stream was created or if the selected connection pool
  ///     is unable to create a stream (if there is too much demand on that pool, for example).
  @inlinable
  internal func makeStream(
    preferredEventLoop: EventLoop?,
    deadline: NIODeadline,
    logger: GRPCLogger,
    streamInitializer initializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
  ) -> PooledStreamChannel {
    let preferredEventLoopID = preferredEventLoop.map { EventLoopID($0) }
    let reservedPool = self.lock.withLock {
      return self._state.reserveStream(preferringPoolWithEventLoopID: preferredEventLoopID).map {
        return self._pools[$0.value]
      }
    }

    switch reservedPool {
    case let .success(pool):
      let channel = pool.makeStream(deadline: deadline, logger: logger, initializer: initializer)
      return PooledStreamChannel(futureResult: channel)

    case let .failure(error):
      let eventLoop = preferredEventLoop ?? self.group.next()
      return PooledStreamChannel(futureResult: eventLoop.makeFailedFuture(error))
    }
  }

  // MARK: Shutdown

  /// Shutdown the pool manager and all connection pools it manages.
  @usableFromInline
  internal func shutdown(mode: ConnectionManager.ShutdownMode, promise: EventLoopPromise<Void>) {
    let (action, pools): (PoolManagerStateMachine.ShutdownAction, [ConnectionPool]?) = self.lock
      .withLock {
        let action = self._state.shutdown(promise: promise)

        switch action {
        case .shutdownPools:
          // Clear out the pools; we need to shut them down.
          let pools = self._pools
          self._pools.removeAll(keepingCapacity: true)
          return (action, pools)

        case .alreadyShutdown, .alreadyShuttingDown:
          return (action, nil)
        }
      }

    switch (action, pools) {
    case let (.shutdownPools, .some(pools)):
      promise.futureResult.whenComplete { _ in self.shutdownComplete() }
      EventLoopFuture.andAllSucceed(pools.map { $0.shutdown(mode: mode) }, promise: promise)

    case let (.alreadyShuttingDown(future), .none):
      promise.completeWith(future)

    case (.alreadyShutdown, .none):
      promise.succeed(())

    case (.shutdownPools, .none),
         (.alreadyShuttingDown, .some),
         (.alreadyShutdown, .some):
      preconditionFailure()
    }
  }

  private func shutdownComplete() {
    self.lock.withLock {
      self._state.shutdownComplete()
    }
  }
}

// MARK: - Connection Pool to Pool Manager

extension PoolManager: StreamLender {
  @usableFromInline
  internal func returnStreams(_ count: Int, to pool: ConnectionPool) {
    self.lock.withLock {
      self._state.returnStreams(count, toPoolOnEventLoopWithID: pool.eventLoop.id)
    }
  }

  @usableFromInline
  internal func changeStreamCapacity(by delta: Int, for pool: ConnectionPool) {
    self.lock.withLock {
      self._state.changeStreamCapacity(by: delta, forPoolOnEventLoopWithID: pool.eventLoop.id)
    }
  }
}

@usableFromInline
internal enum PoolManagerError: Error {
  /// The pool manager has not been initialized yet.
  case notInitialized

  /// The pool manager has been shutdown or is in the process of shutting down.
  case shutdown
}
