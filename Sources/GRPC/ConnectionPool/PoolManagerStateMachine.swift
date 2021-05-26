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

    internal init(
      poolKeys: [PoolManager.ConnectionPoolKey],
      assumedMaxAvailableStreamsPerPool: Int
    ) {
      self.pools = Dictionary(uniqueKeysWithValues: poolKeys.map { key in
        let value = PerPoolState(
          poolIndex: key.index,
          assumedMaxAvailableStreams: assumedMaxAvailableStreamsPerPool
        )
        return (key.eventLoopID, value)
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
  ///   - keys: The index and `EventLoopID` of the pools.
  ///   - capacity: The *assumed* maximum number of streams concurrently available to a pool (that
  ///       is, the product of the assumed value of max concurrent streams and the number of
  ///       connections per pool).
  internal mutating func activatePools(
    keyedBy keys: [PoolManager.ConnectionPoolKey],
    assumingPerPoolCapacity capacity: Int
  ) {
    self.modifyingState { state in
      switch state {
      case .inactive:
        state = .active(.init(poolKeys: keys, assumedMaxAvailableStreamsPerPool: capacity))

      case .active, .shuttingDown, .shutdown, ._modifying:
        preconditionFailure()
      }
    }
  }

  /// Select and reserve a stream from a connection pool.
  mutating func reserveStream(
    preferringPoolWithEventLoopID eventLoopID: EventLoopID?
  ) -> Result<PoolManager.ConnectionPoolIndex, PoolManagerError> {
    return self.modifyingState { state in
      switch state {
      case var .active(active):
        let connectionPoolIndex: PoolManager.ConnectionPoolIndex

        if let index = eventLoopID.flatMap({ eventLoopID in
          active.reserveStreamFromPool(onEventLoopWithID: eventLoopID)
        }) {
          connectionPoolIndex = index
        } else {
          // Nothing on the preferred event loop; fallback to the pool with the most available
          // streams.
          connectionPoolIndex = active.reserveStreamFromPoolWithMostAvailableStreams()
        }

        state = .active(active)
        return .success(connectionPoolIndex)

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
  mutating func returnStreams(_ count: Int, toPoolOnEventLoopWithID eventLoopID: EventLoopID) {
    self.modifyingState { state in
      switch state {
      case var .active(active):
        active.returnStreams(count, toPoolOnEventLoopWithID: eventLoopID)
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
  mutating func changeStreamCapacity(
    by delta: Int,
    forPoolOnEventLoopWithID eventLoopID: EventLoopID
  ) {
    self.modifyingState { state in
      switch state {
      case var .active(active):
        active.increaseMaxAvailableStreams(by: delta, forPoolOnEventLoopWithID: eventLoopID)
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
    case shutdownPools
    case alreadyShutdown
    case alreadyShuttingDown(EventLoopFuture<Void>)
  }

  mutating func shutdown(promise: EventLoopPromise<Void>) -> ShutdownAction {
    self.modifyingState { state in
      switch state {
      case .inactive:
        state = .shutdown
        return .alreadyShutdown

      case .active:
        state = .shuttingDown(promise.futureResult)
        return .shutdownPools

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
  mutating func reserveStreamFromPool(
    onEventLoopWithID eventLoopID: EventLoopID
  ) -> PoolManager.ConnectionPoolIndex? {
    return self.pools[eventLoopID]?.reserveStream()
  }

  mutating func reserveStreamFromPoolWithMostAvailableStreams() -> PoolManager.ConnectionPoolIndex {
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

  mutating func returnStreams(
    _ count: Int,
    toPoolOnEventLoopWithID eventLoopID: EventLoopID
  ) {
    self.pools[eventLoopID]?.returnReservedStreams(count)
  }

  mutating func increaseMaxAvailableStreams(
    by delta: Int,
    forPoolOnEventLoopWithID eventLoopID: EventLoopID
  ) {
    self.pools[eventLoopID]?.maxAvailableStreams += delta
  }
}
