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

import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import XCTest

@testable import GRPC

class PoolManagerStateMachineTests: GRPCTestCase {
  private func makeConnectionPool(
    on eventLoop: EventLoop,
    maxWaiters: Int = 100,
    maxConcurrentStreams: Int = 100,
    loadThreshold: Double = 0.9,
    connectionBackoff: ConnectionBackoff = ConnectionBackoff(),
    makeChannel: @escaping (ConnectionManager, EventLoop) -> EventLoopFuture<Channel>
  ) -> ConnectionPool {
    return ConnectionPool(
      eventLoop: eventLoop,
      maxWaiters: maxWaiters,
      minConnections: 0,
      reservationLoadThreshold: loadThreshold,
      assumedMaxConcurrentStreams: maxConcurrentStreams,
      connectionBackoff: connectionBackoff,
      channelProvider: HookedChannelProvider(makeChannel),
      streamLender: HookedStreamLender(
        onReturnStreams: { _ in },
        onUpdateMaxAvailableStreams: { _ in }
      ),
      delegate: nil,
      logger: self.logger.wrapped
    )
  }

  private func makeInitializedPools(
    group: EmbeddedEventLoopGroup,
    connectionsPerPool: Int = 1
  ) -> [ConnectionPool] {
    let pools = group.loops.map {
      self.makeConnectionPool(on: $0) { _, _ in fatalError() }
    }

    for pool in pools {
      pool.initialize(connections: 1)
    }

    return pools
  }

  private func makeConnectionPoolKeys(
    for pools: [ConnectionPool]
  ) -> [PoolManager.ConnectionPoolKey] {
    return pools.enumerated().map { index, pool in
      return .init(index: .init(index), eventLoopID: pool.eventLoop.id)
    }
  }

  func testReserveStreamOnPreferredEventLoop() {
    let group = EmbeddedEventLoopGroup(loops: 5)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let pools = self.makeInitializedPools(group: group, connectionsPerPool: 1)
    let keys = self.makeConnectionPoolKeys(for: pools)
    var state = PoolManagerStateMachine(
      .active(.init(poolKeys: keys, assumedMaxAvailableStreamsPerPool: 100, statsTask: nil))
    )

    for (index, loop) in group.loops.enumerated() {
      let reservePreferredLoop = state.reserveStream(preferringPoolWithEventLoopID: loop.id)
      reservePreferredLoop.assertSuccess {
        XCTAssertEqual($0, PoolManager.ConnectionPoolIndex(index))
      }
    }
  }

  func testReserveStreamOnPreferredEventLoopWhichNoPoolUses() {
    let group = EmbeddedEventLoopGroup(loops: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let pools = self.makeInitializedPools(group: group, connectionsPerPool: 1)
    let keys = self.makeConnectionPoolKeys(for: pools)
    var state = PoolManagerStateMachine(
      .active(.init(poolKeys: keys, assumedMaxAvailableStreamsPerPool: 100, statsTask: nil))
    )

    let anotherLoop = EmbeddedEventLoop()
    let reservePreferredLoop = state.reserveStream(preferringPoolWithEventLoopID: anotherLoop.id)
    reservePreferredLoop.assertSuccess {
      XCTAssert((0 ..< pools.count).contains($0.value))
    }
  }

  func testReserveStreamWithNoPreferenceReturnsPoolWithHighestAvailability() {
    let group = EmbeddedEventLoopGroup(loops: 5)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let pools = self.makeInitializedPools(group: group, connectionsPerPool: 1)
    let keys = self.makeConnectionPoolKeys(for: pools)
    var state = PoolManagerStateMachine(.inactive)
    state.activatePools(keyedBy: keys, assumingPerPoolCapacity: 100, statsTask: nil)

    // Reserve some streams.
    for (index, loop) in group.loops.enumerated() {
      for _ in 0 ..< 2 * index {
        state.reserveStream(preferringPoolWithEventLoopID: loop.id).assertSuccess()
      }
    }

    // We expect pools[0] to be reserved.
    //     index:   0   1   2   3   4
    // available: 100  98  96  94  92
    state.reserveStream(preferringPoolWithEventLoopID: nil).assertSuccess { poolIndex in
      XCTAssertEqual(poolIndex.value, 0)
    }

    // We expect pools[0] to be reserved again.
    //     index:   0   1   2   3   4
    // available:  99  98  96  94  92
    state.reserveStream(preferringPoolWithEventLoopID: nil).assertSuccess { poolIndex in
      XCTAssertEqual(poolIndex.value, 0)
    }

    // Return some streams to pools[3].
    state.returnStreams(5, toPoolOnEventLoopWithID: pools[3].eventLoop.id)

    // As we returned streams to pools[3] we expect this to be the current state:
    //     index:   0   1   2   3   4
    // available:  98  98  96  99  92
    state.reserveStream(preferringPoolWithEventLoopID: nil).assertSuccess { poolIndex in
      XCTAssertEqual(poolIndex.value, 3)
    }

    // Give an event loop preference for a pool which has more streams reserved.
    state.reserveStream(
      preferringPoolWithEventLoopID: pools[2].eventLoop.id
    ).assertSuccess { poolIndex in
      XCTAssertEqual(poolIndex.value, 2)
    }

    // Update the capacity for one pool, this makes it relatively more available.
    state.changeStreamCapacity(by: 900, forPoolOnEventLoopWithID: pools[4].eventLoop.id)
    // pools[4] has a bunch more streams now:
    //     index:   0   1   2   3    4
    // available:  98  98  96  99  992
    state.reserveStream(preferringPoolWithEventLoopID: nil).assertSuccess { poolIndex in
      XCTAssertEqual(poolIndex.value, 4)
    }
  }

  func testReserveStreamWithNoEventLoopPreference() {
    let group = EmbeddedEventLoopGroup(loops: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let pools = self.makeInitializedPools(group: group, connectionsPerPool: 1)
    let keys = self.makeConnectionPoolKeys(for: pools)
    var state = PoolManagerStateMachine(
      .active(.init(poolKeys: keys, assumedMaxAvailableStreamsPerPool: 100, statsTask: nil))
    )

    let reservePreferredLoop = state.reserveStream(preferringPoolWithEventLoopID: nil)
    reservePreferredLoop.assertSuccess()
  }

  func testReserveStreamWhenInactive() {
    var state = PoolManagerStateMachine(.inactive)
    let action = state.reserveStream(preferringPoolWithEventLoopID: nil)
    action.assertFailure { error in
      XCTAssertEqual(error, .notInitialized)
    }
  }

  func testReserveStreamWhenShuttingDown() {
    let future = EmbeddedEventLoop().makeSucceededFuture(())
    var state = PoolManagerStateMachine(.shuttingDown(future))
    let action = state.reserveStream(preferringPoolWithEventLoopID: nil)
    action.assertFailure { error in
      XCTAssertEqual(error, .shutdown)
    }
  }

  func testReserveStreamWhenShutdown() {
    var state = PoolManagerStateMachine(.shutdown)
    let action = state.reserveStream(preferringPoolWithEventLoopID: nil)
    action.assertFailure { error in
      XCTAssertEqual(error, .shutdown)
    }
  }

  func testShutdownWhenInactive() {
    let loop = EmbeddedEventLoop()
    let promise = loop.makePromise(of: Void.self)

    var state = PoolManagerStateMachine(.inactive)
    let action = state.shutdown(promise: promise)
    action.assertAlreadyShutdown()

    // Don't leak the promise.
    promise.succeed(())
  }

  func testShutdownWhenActive() {
    let group = EmbeddedEventLoopGroup(loops: 5)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let pools = self.makeInitializedPools(group: group, connectionsPerPool: 1)
    let keys = self.makeConnectionPoolKeys(for: pools)
    var state = PoolManagerStateMachine(
      .active(.init(poolKeys: keys, assumedMaxAvailableStreamsPerPool: 100, statsTask: nil))
    )

    let promise = group.loops[0].makePromise(of: Void.self)
    promise.succeed(())

    state.shutdown(promise: promise).assertShutdownPools()
  }

  func testShutdownWhenShuttingDown() {
    let loop = EmbeddedEventLoop()
    let future = loop.makeSucceededVoidFuture()
    var state = PoolManagerStateMachine(.shuttingDown(future))

    let promise = loop.makePromise(of: Void.self)
    promise.succeed(())

    let action = state.shutdown(promise: promise)
    action.assertAlreadyShuttingDown {
      XCTAssert($0 === future)
    }

    // Fully shutdown.
    state.shutdownComplete()
    state.shutdown(promise: promise).assertAlreadyShutdown()
  }

  func testShutdownWhenShutdown() {
    let loop = EmbeddedEventLoop()
    var state = PoolManagerStateMachine(.shutdown)

    let promise = loop.makePromise(of: Void.self)
    promise.succeed(())

    let action = state.shutdown(promise: promise)
    action.assertAlreadyShutdown()
  }
}

// MARK: - Test Helpers

extension Result {
  internal func assertSuccess(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Success) -> Void = { _ in }
  ) {
    if case let .success(value) = self {
      verify(value)
    } else {
      XCTFail("Expected '.success' but got '\(self)'", file: file, line: line)
    }
  }

  internal func assertFailure(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Failure) -> Void = { _ in }
  ) {
    if case let .failure(value) = self {
      verify(value)
    } else {
      XCTFail("Expected '.failure' but got '\(self)'", file: file, line: line)
    }
  }
}

extension PoolManagerStateMachine.ShutdownAction {
  internal func assertShutdownPools(
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    if case .shutdownPools = self {
      ()
    } else {
      XCTFail("Expected '.shutdownPools' but got '\(self)'", file: file, line: line)
    }
  }

  internal func assertAlreadyShuttingDown(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (EventLoopFuture<Void>) -> Void = { _ in }
  ) {
    if case let .alreadyShuttingDown(future) = self {
      verify(future)
    } else {
      XCTFail("Expected '.alreadyShuttingDown' but got '\(self)'", file: file, line: line)
    }
  }

  internal func assertAlreadyShutdown(file: StaticString = #filePath, line: UInt = #line) {
    if case .alreadyShutdown = self {
      ()
    } else {
      XCTFail("Expected '.alreadyShutdown' but got '\(self)'", file: file, line: line)
    }
  }
}

/// An `EventLoopGroup` of `EmbeddedEventLoop`s.
private final class EmbeddedEventLoopGroup: EventLoopGroup {
  internal let loops: [EmbeddedEventLoop]

  internal let lock = NIOLock()
  internal var index = 0

  internal init(loops: Int) {
    self.loops = (0 ..< loops).map { _ in EmbeddedEventLoop() }
  }

  internal func next() -> EventLoop {
    let index: Int = self.lock.withLock {
      let index = self.index
      self.index += 1
      return index
    }
    return self.loops[index % self.loops.count]
  }

  internal func makeIterator() -> EventLoopIterator {
    return EventLoopIterator(self.loops)
  }

  internal func shutdownGracefully(queue: DispatchQueue, _ callback: @escaping (Error?) -> Void) {
    var shutdownError: Error?

    for loop in self.loops {
      loop.shutdownGracefully(queue: queue) { error in
        if let error = error {
          shutdownError = error
        }
      }
    }

    queue.sync {
      callback(shutdownError)
    }
  }
}
