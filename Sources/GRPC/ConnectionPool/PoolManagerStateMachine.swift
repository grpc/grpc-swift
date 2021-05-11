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
import NIO

internal struct PoolManagerStateMachine {
  /// The current state.
  private var state: State

  internal init(_ state: State) {
    self.state = state
  }

  internal enum State {
    case inactive
    case active(ActiveState)
    case shuttingDown(EventLoopFuture<Void>)
    case shutdown
    case _modifying
  }

  internal struct ActiveState {
    internal var pools: [EventLoopID: PerPoolState]

    internal init(pools: [ConnectionPool], assumedMaxAvailableStreamsPerPool: Int) {
      self.pools = Dictionary(uniqueKeysWithValues: pools.map { pool in
        let key = EventLoopID(pool.eventLoop)
        let value = PerPoolState(
          pool: pool,
          assumedMaxAvailableStreams: assumedMaxAvailableStreamsPerPool
        )
        return (key, value)
      })
    }
  }

  /// Temporarily sets `self.state` to `._modifying` before calling the provided closure and setting
  /// `self.state` to the `State` modified by the closure.
  private mutating func modifyingState<Result>(_ modify: (inout State) -> Result) -> Result {
    var state = State._modifying
    swap(&self.state, &state)
    defer {
      self.state = state
    }
    return modify(&state)
  }

  /// Returns whether the pool is shutdown or in the process of shutting down.
  internal var isShutdownOrShuttingDown: Bool {
    switch self.state {
    case .shuttingDown, .shutdown:
      return true
    case .inactive, .active:
      return false
    case ._modifying:
      preconditionFailure()
    }
  }

  /// Activate the pool manager by providing an array of connection pools.
  ///
  /// - Parameters:
  ///   - pools: The pools to activate the pool manager with.
  ///   - capacity: The *assumed* maximum number of streams concurrently available to a pool (that
  ///       is, the product of the assumed value of max concurrent streams and the number of
  ///       connections per pool).
  internal mutating func activate(
    pools: [ConnectionPool],
    assumingPerPoolCapacity capacity: Int
  ) {
    self.modifyingState { state in
      switch state {
      case .inactive:
        state = .active(.init(pools: pools, assumedMaxAvailableStreamsPerPool: capacity))

      case .active, .shuttingDown, .shutdown, ._modifying:
        preconditionFailure()
      }
    }
  }

  /// Select and reserve a stream from a connection pool.
  mutating func reserveStream(
    preferringPoolOnEventLoop eventLoop: EventLoop?
  ) -> Result<ConnectionPool, PoolManagerError> {
    return self.modifyingState { state in
      switch state {
      case var .active(active):
        let connectionPool: ConnectionPool

        if let pool = eventLoop.flatMap({ active.reserveStreamFromPool(runningOnEventLoop: $0) }) {
          connectionPool = pool
        } else {
          // Nothing on the preferred event loop; fallback to the pool with the most available
          // streams.
          connectionPool = active.reserveStreamFromPoolWithMostAvailableStreams()
        }

        state = .active(active)
        return .success(connectionPool)

      case .inactive:
        return .failure(.notInitialized)

      case .shuttingDown, .shutdown:
        return .failure(.shutdown)

      case ._modifying:
        preconditionFailure()
      }
    }
  }

  /// Return streams to the given pool.
  mutating func returnStreams(_ count: Int, to pool: ConnectionPool) {
    self.modifyingState { state in
      switch state {
      case var .active(active):
        active.returnStreams(count, to: pool)
        state = .active(active)

      case .shuttingDown, .shutdown:
        ()

      case .inactive, ._modifying:
        // If the manager is inactive there are no pools which can return streams.
        preconditionFailure()
      }
    }
  }

  /// Update the capacity for the given pool.
  mutating func increaseStreamCapacity(by delta: Int, for pool: ConnectionPool) {
    self.modifyingState { state in
      switch state {
      case var .active(active):
        active.increaseMaxAvailableStreams(by: delta, for: pool)
        state = .active(active)

      case .shuttingDown, .shutdown:
        ()

      case .inactive, ._modifying:
        // If the manager is inactive there are no pools which can update their capacity.
        preconditionFailure()
      }
    }
  }

  enum ShutdownAction {
    case shutdownPools([ConnectionPool])
    case alreadyShutdown
    case alreadyShuttingDown(EventLoopFuture<Void>)
  }

  mutating func shutdown(promise: EventLoopPromise<Void>) -> ShutdownAction {
    self.modifyingState { state in
      switch state {
      case .inactive:
        state = .shutdown
        return .alreadyShutdown

      case let .active(active):
        state = .shuttingDown(promise.futureResult)
        return .shutdownPools(active.pools.values.map { $0.pool })

      case let .shuttingDown(future):
        return .alreadyShuttingDown(future)

      case .shutdown:
        return .alreadyShutdown

      case ._modifying:
        preconditionFailure()
      }
    }
  }

  mutating func shutdownComplete() {
    self.modifyingState { state in
      switch state {
      case .shuttingDown:
        state = .shutdown

      case .inactive, .active, .shutdown, ._modifying:
        preconditionFailure()
      }
    }
  }
}

extension PoolManagerStateMachine.ActiveState {
  mutating func reserveStreamFromPool(runningOnEventLoop eventLoop: EventLoop) -> ConnectionPool? {
    return self.pools[EventLoopID(eventLoop)]?.reserveStream()
  }

  mutating func reserveStreamFromPoolWithMostAvailableStreams() -> ConnectionPool {
    // We don't allow pools to be empty (while active).
    assert(!self.pools.isEmpty)

    var mostAvailableStreams = Int.min
    var mostAvailableIndex = self.pools.values.startIndex
    var index = mostAvailableIndex

    while index != self.pools.values.endIndex {
      let availableStreams = self.pools.values[index].availableStreams

      if availableStreams > mostAvailableStreams {
        mostAvailableIndex = index
        mostAvailableStreams = availableStreams
      }

      self.pools.values.formIndex(after: &index)
    }

    return self.pools.values[mostAvailableIndex].reserveStream()
  }

  mutating func returnStreams(_ count: Int, to pool: ConnectionPool) {
    self.pools[EventLoopID(pool.eventLoop)]?.returnReservedStreams(count)
  }

  mutating func increaseMaxAvailableStreams(by delta: Int, for pool: ConnectionPool) {
    self.pools[EventLoopID(pool.eventLoop)]?.maxAvailableStreams += delta
  }
}
