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
import NIOCore
import NIOEmbedded
import NIOHTTP2
import XCTest

@testable import GRPC

final class ConnectionPoolTests: GRPCTestCase {
  private enum TestError: Error {
    case noChannelExpected
  }

  private var eventLoop: EmbeddedEventLoop!
  private var tearDownBlocks: [() throws -> Void] = []

  override func setUp() {
    super.setUp()
    self.eventLoop = EmbeddedEventLoop()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.eventLoop.close())
    self.tearDownBlocks.forEach { try? $0() }
    super.tearDown()
  }

  private func noChannelExpected(
    _: ConnectionManager,
    _ eventLoop: EventLoop,
    line: UInt = #line
  ) -> EventLoopFuture<Channel> {
    XCTFail("Channel unexpectedly created", line: line)
    return eventLoop.makeFailedFuture(TestError.noChannelExpected)
  }

  private func makePool(
    waiters: Int = 1000,
    reservationLoadThreshold: Double = 0.9,
    minConnections: Int = 0,
    assumedMaxConcurrentStreams: Int = 100,
    now: @escaping () -> NIODeadline = { .now() },
    connectionBackoff: ConnectionBackoff = ConnectionBackoff(),
    delegate: GRPCConnectionPoolDelegate? = nil,
    onReservationReturned: @escaping (Int) -> Void = { _ in },
    onMaximumReservationsChange: @escaping (Int) -> Void = { _ in },
    channelProvider: ConnectionManagerChannelProvider
  ) -> ConnectionPool {
    return ConnectionPool(
      eventLoop: self.eventLoop,
      maxWaiters: waiters,
      minConnections: minConnections,
      reservationLoadThreshold: reservationLoadThreshold,
      assumedMaxConcurrentStreams: assumedMaxConcurrentStreams,
      connectionBackoff: connectionBackoff,
      channelProvider: channelProvider,
      streamLender: HookedStreamLender(
        onReturnStreams: onReservationReturned,
        onUpdateMaxAvailableStreams: onMaximumReservationsChange
      ),
      delegate: delegate,
      logger: self.logger.wrapped,
      now: now
    )
  }

  private func makePool(
    waiters: Int = 1000,
    delegate: GRPCConnectionPoolDelegate? = nil,
    makeChannel: @escaping (ConnectionManager, EventLoop) -> EventLoopFuture<Channel>
  ) -> ConnectionPool {
    return self.makePool(
      waiters: waiters,
      delegate: delegate,
      channelProvider: HookedChannelProvider(makeChannel)
    )
  }

  private func setUpPoolAndController(
    waiters: Int = 1000,
    reservationLoadThreshold: Double = 0.9,
    now: @escaping () -> NIODeadline = { .now() },
    connectionBackoff: ConnectionBackoff = ConnectionBackoff(),
    delegate: GRPCConnectionPoolDelegate? = nil,
    onReservationReturned: @escaping (Int) -> Void = { _ in },
    onMaximumReservationsChange: @escaping (Int) -> Void = { _ in }
  ) -> (ConnectionPool, ChannelController) {
    let controller = ChannelController()
    let pool = self.makePool(
      waiters: waiters,
      reservationLoadThreshold: reservationLoadThreshold,
      now: now,
      connectionBackoff: connectionBackoff,
      delegate: delegate,
      onReservationReturned: onReservationReturned,
      onMaximumReservationsChange: onMaximumReservationsChange,
      channelProvider: controller
    )

    self.tearDownBlocks.append {
      let shutdown = pool.shutdown()
      self.eventLoop.run()
      XCTAssertNoThrow(try shutdown.wait())
      controller.finish()
    }

    return (pool, controller)
  }

  func testEmptyConnectionPool() {
    let pool = self.makePool {
      self.noChannelExpected($0, $1)
    }
    XCTAssertEqual(pool.sync.connections, 0)
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)

    pool.initialize(connections: 20)
    XCTAssertEqual(pool.sync.connections, 20)
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)

    let shutdownFuture = pool.shutdown()
    self.eventLoop.run()
    XCTAssertNoThrow(try shutdownFuture.wait())
  }

  func testShutdownEmptyPool() {
    let pool = self.makePool {
      self.noChannelExpected($0, $1)
    }
    XCTAssertNoThrow(try pool.shutdown().wait())
    // Shutting down twice should also be fine.
    XCTAssertNoThrow(try pool.shutdown().wait())
  }

  func testMakeStreamWhenShutdown() {
    let pool = self.makePool {
      self.noChannelExpected($0, $1)
    }
    XCTAssertNoThrow(try pool.shutdown().wait())

    let stream = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    XCTAssertThrowsError(try stream.wait()) { error in
      XCTAssert((error as? GRPCConnectionPoolError).isShutdown)
    }
  }

  func testMakeStreamWhenWaiterQueueIsFull() {
    let maxWaiters = 5
    let pool = self.makePool(waiters: maxWaiters) {
      self.noChannelExpected($0, $1)
    }

    let waiting = (0 ..< maxWaiters).map { _ in
      return pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }

    let tooManyWaiters = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    XCTAssertThrowsError(try tooManyWaiters.wait()) { error in
      XCTAssert((error as? GRPCConnectionPoolError).isTooManyWaiters)
    }

    XCTAssertNoThrow(try pool.shutdown().wait())
    // All 'waiting' futures will be failed by the shutdown promise.
    for waiter in waiting {
      XCTAssertThrowsError(try waiter.wait()) { error in
        XCTAssert((error as? GRPCConnectionPoolError).isShutdown)
      }
    }
  }

  func testWaiterTimingOut() {
    let pool = self.makePool {
      self.noChannelExpected($0, $1)
    }

    let waiter = pool.makeStream(deadline: .uptimeNanoseconds(10), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertEqual(pool.sync.waiters, 1)

    self.eventLoop.advanceTime(to: .uptimeNanoseconds(10))
    XCTAssertThrowsError(try waiter.wait()) { error in
      XCTAssert((error as? GRPCConnectionPoolError).isDeadlineExceeded)
    }

    XCTAssertEqual(pool.sync.waiters, 0)
  }

  func testWaiterTimingOutInPast() {
    let pool = self.makePool {
      self.noChannelExpected($0, $1)
    }

    self.eventLoop.advanceTime(to: .uptimeNanoseconds(10))

    let waiter = pool.makeStream(deadline: .uptimeNanoseconds(5), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertEqual(pool.sync.waiters, 1)

    self.eventLoop.run()
    XCTAssertThrowsError(try waiter.wait()) { error in
      XCTAssert((error as? GRPCConnectionPoolError).isDeadlineExceeded)
    }

    XCTAssertEqual(pool.sync.waiters, 0)
  }

  func testMakeStreamTriggersChannelCreation() {
    let (pool, controller) = self.setUpPoolAndController()

    pool.initialize(connections: 1)
    XCTAssertEqual(pool.sync.connections, 1)
    // No channels yet.
    XCTAssertEqual(controller.count, 0)

    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()

    // We should have been asked for a channel now.
    XCTAssertEqual(controller.count, 1)
    // The connection isn't ready yet though, so no streams available.
    XCTAssertEqual(pool.sync.availableStreams, 0)

    // Make the connection 'ready'.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)

    // We have a multiplexer and a 'ready' connection.
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.availableStreams, 9)
    XCTAssertEqual(pool.sync.waiters, 0)

    // Run the loop to create the stream, we need to fire the event too.
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())
    controller.openStreamInChannel(atIndex: 0)

    // Now close the stream.
    controller.closeStreamInChannel(atIndex: 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.availableStreams, 10)
  }

  func testMakeStreamWhenConnectionIsAlreadyAvailable() {
    let (pool, controller) = self.setUpPoolAndController()
    pool.initialize(connections: 1)

    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 1)

    // Fire up the connection.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)

    // Run the loop to create the stream, we need to fire the stream creation event too.
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())
    controller.openStreamInChannel(atIndex: 0)

    // Now we can create another stream, but as there's already an available stream on an active
    // connection we won't have to wait.
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    let notWaiting = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Still no waiters.
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 2)

    // Run the loop to create the stream, we need to fire the stream creation event too.
    self.eventLoop.run()
    XCTAssertNoThrow(try notWaiting.wait())
    controller.openStreamInChannel(atIndex: 0)
  }

  func testMakeMoreWaitersThanConnectionCanHandle() {
    var returnedStreams: [Int] = []
    let (pool, controller) = self.setUpPoolAndController(onReservationReturned: {
      returnedStreams.append($0)
    })
    pool.initialize(connections: 1)

    // Enqueue twice as many waiters as the connection will be able to handle.
    let maxConcurrentStreams = 10
    let waiters = (0 ..< maxConcurrentStreams * 2).map { _ in
      return pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }

    XCTAssertEqual(pool.sync.waiters, 2 * maxConcurrentStreams)

    // Fire up the connection.
    self.eventLoop.run()
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: maxConcurrentStreams)

    // We should have assigned a bunch of streams to waiters now.
    XCTAssertEqual(pool.sync.waiters, maxConcurrentStreams)
    XCTAssertEqual(pool.sync.reservedStreams, maxConcurrentStreams)
    XCTAssertEqual(pool.sync.availableStreams, 0)

    // Do the stream creation and make sure the first batch are succeeded.
    self.eventLoop.run()
    let firstBatch = waiters.prefix(maxConcurrentStreams)
    var others = waiters.dropFirst(maxConcurrentStreams)

    for waiter in firstBatch {
      XCTAssertNoThrow(try waiter.wait())
      controller.openStreamInChannel(atIndex: 0)
    }

    // Close a stream.
    controller.closeStreamInChannel(atIndex: 0)
    XCTAssertEqual(returnedStreams, [1])
    // We have another stream so a waiter should be succeeded.
    XCTAssertEqual(pool.sync.waiters, maxConcurrentStreams - 1)
    self.eventLoop.run()
    XCTAssertNoThrow(try others.popFirst()?.wait())

    // Shutdown the pool: the remaining waiters should be failed.
    let shutdown = pool.shutdown()
    self.eventLoop.run()
    XCTAssertNoThrow(try shutdown.wait())
    for waiter in others {
      XCTAssertThrowsError(try waiter.wait()) { error in
        XCTAssert((error as? GRPCConnectionPoolError).isShutdown)
      }
    }
  }

  func testDropConnectionWithOutstandingReservations() {
    var streamsReturned: [Int] = []
    let (pool, controller) = self.setUpPoolAndController(
      onReservationReturned: { streamsReturned.append($0) }
    )
    pool.initialize(connections: 1)

    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 1)

    // Fire up the connection.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)

    // Run the loop to create the stream, we need to fire the stream creation event too.
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())
    controller.openStreamInChannel(atIndex: 0)

    // Create a handful of streams.
    XCTAssertEqual(pool.sync.availableStreams, 9)
    for _ in 0 ..< 5 {
      let notWaiting = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
      self.eventLoop.run()
      XCTAssertNoThrow(try notWaiting.wait())
      controller.openStreamInChannel(atIndex: 0)
    }

    XCTAssertEqual(pool.sync.availableStreams, 4)
    XCTAssertEqual(pool.sync.reservedStreams, 6)

    // Blast the connection away. We'll be notified about dropped reservations.
    XCTAssertEqual(streamsReturned, [])
    controller.throwError(ChannelError.ioOnClosedChannel, inChannelAtIndex: 0)
    controller.fireChannelInactiveForChannel(atIndex: 0)
    XCTAssertEqual(streamsReturned, [6])

    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
  }

  func testDropConnectionWithOutstandingReservationsAndWaiters() {
    var streamsReturned: [Int] = []
    let (pool, controller) = self.setUpPoolAndController(
      onReservationReturned: { streamsReturned.append($0) }
    )
    pool.initialize(connections: 1)

    // Reserve a bunch of streams.
    let waiters = (0 ..< 10).map { _ in
      return pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }

    // Connect and setup all the streams.
    self.eventLoop.run()
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)
    self.eventLoop.run()
    for waiter in waiters {
      XCTAssertNoThrow(try waiter.wait())
      controller.openStreamInChannel(atIndex: 0)
    }

    // All streams should be reserved.
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 10)

    // Add a waiter.
    XCTAssertEqual(pool.sync.waiters, 0)
    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertEqual(pool.sync.waiters, 1)

    // Now bork the connection. We'll be notified about the 10 dropped reservation but not the one
    // waiter .
    XCTAssertEqual(streamsReturned, [])
    controller.throwError(ChannelError.ioOnClosedChannel, inChannelAtIndex: 0)
    controller.fireChannelInactiveForChannel(atIndex: 0)
    XCTAssertEqual(streamsReturned, [10])

    // The connection dropped, let the reconnect kick in.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 2)

    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1, maxConcurrentStreams: 10)
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())
    controller.openStreamInChannel(atIndex: 1)
    controller.closeStreamInChannel(atIndex: 1)
    XCTAssertEqual(streamsReturned, [10, 1])

    XCTAssertEqual(pool.sync.availableStreams, 10)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
  }

  func testDeadlineExceededInSameTickAsSucceedingWaiters() {
    // deadline must be exceeded just as servicing waiter is done

    // - setup waiter with deadline x
    // - start connecting
    // - set time to x
    // - finish connecting

    let (pool, controller) = self.setUpPoolAndController(now: {
      return NIODeadline.uptimeNanoseconds(12)
    })
    pool.initialize(connections: 1)

    let waiter1 = pool.makeStream(deadline: .uptimeNanoseconds(10), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    let waiter2 = pool.makeStream(deadline: .uptimeNanoseconds(15), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // Start creating the channel.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 1)

    // Fire up the connection.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)

    // The deadline for the first waiter is already after 'now', so it'll fail with deadline
    // exceeded.
    self.eventLoop.run()
    // We need to advance the time to fire the timeout to fail the waiter.
    self.eventLoop.advanceTime(to: .uptimeNanoseconds(10))
    XCTAssertThrowsError(try waiter1.wait()) { error in
      XCTAssert((error as? GRPCConnectionPoolError).isDeadlineExceeded)
    }

    self.eventLoop.run()
    XCTAssertNoThrow(try waiter2.wait())
    controller.openStreamInChannel(atIndex: 0)

    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.availableStreams, 9)

    controller.closeStreamInChannel(atIndex: 0)
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.availableStreams, 10)
  }

  func testConnectionsAreBroughtUpAtAppropriateTimes() {
    let (pool, controller) = self.setUpPoolAndController(reservationLoadThreshold: 0.2)
    // We'll allow 3 connections and configure max concurrent streams to 10. With our reservation
    // threshold we'll bring up a new connection after enqueueing the 1st, 2nd and 4th waiters.
    pool.initialize(connections: 3)
    let maxConcurrentStreams = 10

    // No demand so all three connections are idle.
    XCTAssertEqual(pool.sync.idleConnections, 3)

    let w1 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // demand=1, available=0, load=infinite, one connection should be non-idle
    XCTAssertEqual(pool.sync.idleConnections, 2)

    // Connect the first channel and write the first settings frame; this allows us to lower the
    // default max concurrent streams value (from 100).
    self.eventLoop.run()
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: maxConcurrentStreams)

    self.eventLoop.run()
    XCTAssertNoThrow(try w1.wait())
    controller.openStreamInChannel(atIndex: 0)

    let w2 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    self.eventLoop.run()
    XCTAssertNoThrow(try w2.wait())
    controller.openStreamInChannel(atIndex: 0)

    // demand=2, available=10, load=0.2; only one idle connection now.
    XCTAssertEqual(pool.sync.idleConnections, 1)

    // Add more demand before the second connection comes up.
    let w3 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // demand=3, available=20, load=0.15; still one idle connection.
    XCTAssertEqual(pool.sync.idleConnections, 1)

    // Connection the next channel
    self.eventLoop.run()
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1, maxConcurrentStreams: maxConcurrentStreams)

    XCTAssertNoThrow(try w3.wait())
    controller.openStreamInChannel(atIndex: 1)
  }

  func testQuiescingConnectionIsReplaced() {
    var reservationsReturned: [Int] = []
    let (pool, controller) = self.setUpPoolAndController(onReservationReturned: {
      reservationsReturned.append($0)
    })
    pool.initialize(connections: 1)
    XCTAssertEqual(pool.sync.connections, 1)

    let w1 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()

    // Make the connection 'ready'.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0)

    // Run the loop to create the stream.
    self.eventLoop.run()
    XCTAssertNoThrow(try w1.wait())
    controller.openStreamInChannel(atIndex: 0)

    // One stream reserved by 'w1' on the only connection in the pool (which isn't idle).
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.connections, 1)
    XCTAssertEqual(pool.sync.idleConnections, 0)

    // Quiesce the connection. It should be punted from the pool and any active RPCs allowed to run
    // their course. A new (idle) connection should replace it in the pool.
    controller.sendGoAwayToChannel(atIndex: 0)

    // The quiescing connection had 1 stream reserved, it's now returned to the outer pool and we
    // have a new idle connection in place of the old one.
    XCTAssertEqual(reservationsReturned, [1])
    // The inner pool still knows about the reserved stream.
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.idleConnections, 1)

    // Ask for another stream: this will be on the new idle connection.
    let w2 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 2)

    // Make the connection 'ready'.
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1)

    self.eventLoop.run()
    XCTAssertNoThrow(try w2.wait())
    controller.openStreamInChannel(atIndex: 1)

    // The stream on the quiescing connection is still reserved.
    XCTAssertEqual(pool.sync.reservedStreams, 2)
    XCTAssertEqual(pool.sync.availableStreams, 99)

    // Return a stream for the _quiescing_ connection: nothing should change in the pool.
    controller.closeStreamInChannel(atIndex: 0)

    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.availableStreams, 99)

    // Return a stream for the new connection.
    controller.closeStreamInChannel(atIndex: 1)

    XCTAssertEqual(reservationsReturned, [1, 1])
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.availableStreams, 100)
  }

  func testBackoffIsUsedForReconnections() {
    // Fix backoff to always be 1 second.
    let backoff = ConnectionBackoff(
      initialBackoff: 1.0,
      maximumBackoff: 1.0,
      multiplier: 1.0,
      jitter: 0.0
    )

    let (pool, controller) = self.setUpPoolAndController(connectionBackoff: backoff)
    pool.initialize(connections: 1)
    XCTAssertEqual(pool.sync.connections, 1)

    let w1 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()

    // Make the connection 'ready'.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0)
    self.eventLoop.run()
    XCTAssertNoThrow(try w1.wait())
    controller.openStreamInChannel(atIndex: 0)

    // Close the connection. It should hit the transient failure state.
    controller.fireChannelInactiveForChannel(atIndex: 0)
    // Now nothing is available in the pool.
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.idleConnections, 0)

    // Enqueue two waiters. One to time out before the reconnect happens.
    let w2 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    let w3 = pool.makeStream(
      deadline: .uptimeNanoseconds(UInt64(TimeAmount.milliseconds(500).nanoseconds)),
      logger: self.logger.wrapped
    ) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    XCTAssertEqual(pool.sync.waiters, 2)

    // Time out w3.
    self.eventLoop.advanceTime(by: .milliseconds(500))
    XCTAssertThrowsError(try w3.wait())
    XCTAssertEqual(pool.sync.waiters, 1)

    // Wait a little more for the backoff to pass. The controller should now have a second channel.
    self.eventLoop.advanceTime(by: .milliseconds(500))
    XCTAssertEqual(controller.count, 2)

    // Start up the next channel.
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1)
    self.eventLoop.run()
    XCTAssertNoThrow(try w2.wait())
    controller.openStreamInChannel(atIndex: 1)
  }

  func testFailedWaiterWithError() throws {
    // We want to check a few things in this test:
    //
    // 1. When an active channel throws an error that any waiter in the connection pool which has
    //    its deadline exceeded or any waiter which exceeds the waiter limit fails with an error
    //    which includes the underlying channel error.
    // 2. When a reconnect happens and the pool is just busy, no underlying error is passed through
    //    to failing waiters.

    // Fix backoff to always be 1 second. This is necessary to figure out timings later on when
    // we try to establish a new connection.
    let backoff = ConnectionBackoff(
      initialBackoff: 1.0,
      maximumBackoff: 1.0,
      multiplier: 1.0,
      jitter: 0.0
    )

    let (pool, controller) = self.setUpPoolAndController(waiters: 10, connectionBackoff: backoff)
    pool.initialize(connections: 1)

    // First we'll create two streams which will fail for different reasons.
    // - w1 will fail because of a timeout (no channel came up before the waiters own deadline
    //   passed but no connection has previously failed)
    // - w2 will fail because of a timeout but after the underlying channel has failed to connect so
    //   should have that additional failure information.
    let w1 = pool.makeStream(deadline: .uptimeNanoseconds(10), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    let w2 = pool.makeStream(deadline: .uptimeNanoseconds(20), logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // Start creating the channel.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 1)

    // Fire up the connection.
    controller.connectChannel(atIndex: 0)

    // Advance time to fail the w1.
    self.eventLoop.advanceTime(to: .uptimeNanoseconds(10))

    XCTAssertThrowsError(try w1.wait()) { error in
      switch error as? GRPCConnectionPoolError {
      case .some(let error):
        XCTAssertEqual(error.code, .deadlineExceeded)
        XCTAssertNil(error.underlyingError)
        // Deadline exceeded but no underlying error, as expected.
        ()
      default:
        XCTFail("Expected ConnectionPoolError.deadlineExceeded(.none) but got \(error)")
      }
    }

    // Now fail the connection and timeout w2.
    struct DummyError: Error {}
    controller.throwError(DummyError(), inChannelAtIndex: 0)
    controller.fireChannelInactiveForChannel(atIndex: 0)
    self.eventLoop.advanceTime(to: .uptimeNanoseconds(20))

    XCTAssertThrowsError(try w2.wait()) { error in
      switch error as? GRPCConnectionPoolError {
      case let .some(error):
        XCTAssertEqual(error.code, .deadlineExceeded)
        // Deadline exceeded and we have the underlying error.
        XCTAssert(error.underlyingError is DummyError)
      default:
        XCTFail("Expected ConnectionPoolError.deadlineExceeded(.some) but got \(error)")
      }
    }

    // For the next part of the test we want to validate that when a new channel is created after
    // the backoff period passes that no additional errors are attached when the pool is just busy
    // but otherwise operational.
    //
    // To do this we'll create a bunch of waiters. These will be succeeded when the new connection
    // comes up and, importantly, use up all available streams on that connection.
    //
    // We'll then enqueue enough waiters to fill the waiter queue. We'll then validate that one more
    // waiter trips over the queue limit but does not include the connection error we saw earlier.
    // We'll then timeout the waiters in the queue and validate the same thing.

    // These streams should succeed when the new connection is up. We'll limit the connection to 10
    // streams when we bring it up.
    let streams = (0 ..< 10).map { _ in
      pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }

    // The connection is backing off; advance time to create another channel.
    XCTAssertEqual(controller.count, 1)
    self.eventLoop.advanceTime(by: .seconds(1))
    XCTAssertEqual(controller.count, 2)
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1, maxConcurrentStreams: 10)
    self.eventLoop.run()

    // Make sure the streams are succeeded.
    for stream in streams {
      XCTAssertNoThrow(try stream.wait())
      controller.openStreamInChannel(atIndex: 1)
    }

    // All streams should be reserved.
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 10)
    XCTAssertEqual(pool.sync.waiters, 0)

    // We configured the pool to allow for 10 waiters, so let's enqueue that many which will time
    // out at a known point in time.
    let now = NIODeadline.now()
    self.eventLoop.advanceTime(to: now)
    let waiters = (0 ..< 10).map { _ in
      pool.makeStream(deadline: now + .seconds(1), logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }

    // This is one waiter more than is allowed so it should hit too-many-waiters. We don't expect
    // an inner error though, the connection is just busy.
    let tooManyWaiters = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertThrowsError(try tooManyWaiters.wait()) { error in
      switch error as? GRPCConnectionPoolError {
      case .some(let error):
        XCTAssertEqual(error.code, .tooManyWaiters)
        XCTAssertNil(error.underlyingError)
      default:
        XCTFail("Expected ConnectionPoolError.tooManyWaiters(.none) but got \(error)")
      }
    }

    // Finally, timeout the remaining waiters. Again, no inner error, the connection is just busy.
    self.eventLoop.advanceTime(by: .seconds(1))
    for waiter in waiters {
      XCTAssertThrowsError(try waiter.wait()) { error in
        switch error as? GRPCConnectionPoolError {
        case .some(let error):
          XCTAssertEqual(error.code, .deadlineExceeded)
          XCTAssertNil(error.underlyingError)
        default:
          XCTFail("Expected ConnectionPoolError.deadlineExceeded(.none) but got \(error)")
        }
      }
    }
  }

  func testWaiterStoresItsScheduledTask() throws {
    let deadline = NIODeadline.uptimeNanoseconds(42)
    let promise = self.eventLoop.makePromise(of: Channel.self)
    let waiter = ConnectionPool.Waiter(deadline: deadline, promise: promise) {
      return $0.eventLoop.makeSucceededVoidFuture()
    }

    XCTAssertNil(waiter._scheduledTimeout)

    waiter.scheduleTimeout(on: self.eventLoop) {
      waiter.fail(GRPCConnectionPoolError.deadlineExceeded(connectionError: nil))
    }

    XCTAssertNotNil(waiter._scheduledTimeout)
    self.eventLoop.advanceTime(to: deadline)
    XCTAssertThrowsError(try promise.futureResult.wait())
    XCTAssertNil(waiter._scheduledTimeout)
  }

  func testReturnStreamAfterConnectionCloses() throws {
    var returnedStreams = 0
    let (pool, controller) = self.setUpPoolAndController(onReservationReturned: { returned in
      returnedStreams += returned
    })
    pool.initialize(connections: 1)

    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()
    XCTAssertEqual(controller.count, 1)

    // Fire up the connection.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)

    // Run the loop to create the stream, we need to fire the stream creation event too.
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())
    controller.openStreamInChannel(atIndex: 0)

    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 9)
    XCTAssertEqual(pool.sync.reservedStreams, 1)
    XCTAssertEqual(pool.sync.connections, 1)

    // Close all streams on connection 0.
    let error = GRPCStatus(code: .internalError, message: nil)
    controller.throwError(error, inChannelAtIndex: 0)
    controller.fireChannelInactiveForChannel(atIndex: 0)
    XCTAssertEqual(returnedStreams, 1)

    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.connections, 1)

    // The connection is closed so the stream shouldn't be returned again.
    controller.closeStreamInChannel(atIndex: 0)
    XCTAssertEqual(returnedStreams, 1)
  }

  func testConnectionPoolDelegate() throws {
    let recorder = EventRecordingConnectionPoolDelegate()
    let (pool, controller) = self.setUpPoolAndController(delegate: recorder)
    pool.initialize(connections: 2)

    func assertConnectionAdded(
      _ event: EventRecordingConnectionPoolDelegate.Event?
    ) throws -> GRPCConnectionID {
      let unwrappedEvent = try XCTUnwrap(event)
      switch unwrappedEvent {
      case let .connectionAdded(id):
        return id
      default:
        throw EventRecordingConnectionPoolDelegate.UnexpectedEvent(unwrappedEvent)
      }
    }

    let connID1 = try assertConnectionAdded(recorder.popFirst())
    let connID2 = try assertConnectionAdded(recorder.popFirst())

    let waiter = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    // Start creating the channel.
    self.eventLoop.run()

    let startedConnecting = recorder.popFirst()
    let firstConn: GRPCConnectionID
    let secondConn: GRPCConnectionID

    if startedConnecting == .startedConnecting(connID1) {
      firstConn = connID1
      secondConn = connID2
    } else if startedConnecting == .startedConnecting(connID2) {
      firstConn = connID2
      secondConn = connID1
    } else {
      return XCTFail("Unexpected event")
    }

    // Connect the connection.
    self.eventLoop.run()
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0, maxConcurrentStreams: 10)
    XCTAssertEqual(recorder.popFirst(), .connectSucceeded(firstConn, 10))

    // Open a stream for the waiter.
    controller.openStreamInChannel(atIndex: 0)
    XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(firstConn, 1, 10))
    self.eventLoop.run()
    XCTAssertNoThrow(try waiter.wait())

    // Okay, more utilization!
    for n in 2 ... 8 {
      let w = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
        $0.eventLoop.makeSucceededVoidFuture()
      }

      controller.openStreamInChannel(atIndex: 0)
      XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(firstConn, n, 10))
      self.eventLoop.run()
      XCTAssertNoThrow(try w.wait())
    }

    // The utilisation threshold before bringing up a new connection is 0.9; we have 8 open streams
    // (out of 10) now so opening the next should trigger a connect on the other connection.
    let w9 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertEqual(recorder.popFirst(), .startedConnecting(secondConn))

    // Deal with the 9th stream.
    controller.openStreamInChannel(atIndex: 0)
    XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(firstConn, 9, 10))
    self.eventLoop.run()
    XCTAssertNoThrow(try w9.wait())

    // Bring up the next connection.
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1, maxConcurrentStreams: 10)
    XCTAssertEqual(recorder.popFirst(), .connectSucceeded(secondConn, 10))

    // The next stream should be on the new connection.
    let w10 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // Deal with the 10th stream.
    controller.openStreamInChannel(atIndex: 1)
    XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(secondConn, 1, 10))
    self.eventLoop.run()
    XCTAssertNoThrow(try w10.wait())

    // Close the streams.
    for i in 1 ... 9 {
      controller.closeStreamInChannel(atIndex: 0)
      XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(firstConn, 9 - i, 10))
    }

    controller.closeStreamInChannel(atIndex: 1)
    XCTAssertEqual(recorder.popFirst(), .connectionUtilizationChanged(secondConn, 0, 10))

    // Close the connections.
    controller.fireChannelInactiveForChannel(atIndex: 0)
    XCTAssertEqual(recorder.popFirst(), .connectionClosed(firstConn))
    controller.fireChannelInactiveForChannel(atIndex: 1)
    XCTAssertEqual(recorder.popFirst(), .connectionClosed(secondConn))

    // All conns are already closed.
    let shutdownFuture = pool.shutdown()
    self.eventLoop.run()
    XCTAssertNoThrow(try shutdownFuture.wait())

    // Two connections must be removed.
    for _ in 0 ..< 2 {
      if let event = recorder.popFirst() {
        let id = event.id
        XCTAssertEqual(event, .connectionRemoved(id))
      } else {
        XCTFail("Expected .connectionRemoved")
      }
    }
  }

  func testConnectionPoolErrorDescription() {
    var error = GRPCConnectionPoolError(code: .deadlineExceeded)
    XCTAssertEqual(String(describing: error), "deadlineExceeded")
    error.code = .shutdown
    XCTAssertEqual(String(describing: error), "shutdown")
    error.code = .tooManyWaiters
    XCTAssertEqual(String(describing: error), "tooManyWaiters")

    struct DummyError: Error {}
    error.underlyingError = DummyError()
    XCTAssertEqual(String(describing: error), "tooManyWaiters (DummyError())")
  }

  func testConnectionPoolErrorCodeEquality() {
    let error = GRPCConnectionPoolError(code: .deadlineExceeded)
    XCTAssertEqual(error.code, .deadlineExceeded)
    XCTAssertNotEqual(error.code, .shutdown)
  }

  func testMinimumConnectionsAreOpenRightAfterInitializing() {
    let controller = ChannelController()
    let pool = self.makePool(minConnections: 5, channelProvider: controller)

    pool.initialize(connections: 20)
    self.eventLoop.run()

    XCTAssertEqual(pool.sync.connections, 20)
    XCTAssertEqual(pool.sync.idleConnections, 15)
    XCTAssertEqual(pool.sync.activeConnections, 5)
    XCTAssertEqual(pool.sync.waiters, 0)
    XCTAssertEqual(pool.sync.availableStreams, 0)
    XCTAssertEqual(pool.sync.reservedStreams, 0)
    XCTAssertEqual(pool.sync.transientFailureConnections, 0)
  }

  func testMinimumConnectionsAreOpenAfterOneIsQuiesced() {
    let controller = ChannelController()
    let pool = self.makePool(
      minConnections: 1,
      assumedMaxConcurrentStreams: 1,
      channelProvider: controller
    )

    // Initialize two connections, and make sure that only one of them is active,
    // since we have set minConnections to 1.
    pool.initialize(connections: 2)
    self.eventLoop.run()
    XCTAssertEqual(pool.sync.connections, 2)
    XCTAssertEqual(pool.sync.idleConnections, 1)
    XCTAssertEqual(pool.sync.activeConnections, 1)
    XCTAssertEqual(pool.sync.transientFailureConnections, 0)

    // Open two streams, which, because the maxConcurrentStreams is 1, will
    // create two channels.
    let w1 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }
    let w2 = pool.makeStream(deadline: .distantFuture, logger: self.logger.wrapped) {
      $0.eventLoop.makeSucceededVoidFuture()
    }

    // Start creating the channels.
    self.eventLoop.run()

    // Make both connections ready.
    controller.connectChannel(atIndex: 0)
    controller.sendSettingsToChannel(atIndex: 0)
    controller.connectChannel(atIndex: 1)
    controller.sendSettingsToChannel(atIndex: 1)

    // Run the loop to create the streams/connections.
    self.eventLoop.run()
    XCTAssertNoThrow(try w1.wait())
    controller.openStreamInChannel(atIndex: 0)
    XCTAssertNoThrow(try w2.wait())
    controller.openStreamInChannel(atIndex: 1)

    XCTAssertEqual(pool.sync.connections, 2)
    XCTAssertEqual(pool.sync.idleConnections, 0)
    XCTAssertEqual(pool.sync.activeConnections, 2)
    XCTAssertEqual(pool.sync.transientFailureConnections, 0)

    // Quiesce the connection that should be kept alive.
    // Another connection should be brought back up immediately after, to maintain
    // the minimum number of active connections that won't go idle.
    controller.sendGoAwayToChannel(atIndex: 0)
    XCTAssertEqual(pool.sync.connections, 3)
    XCTAssertEqual(pool.sync.idleConnections, 1)
    XCTAssertEqual(pool.sync.activeConnections, 2)
    XCTAssertEqual(pool.sync.transientFailureConnections, 0)

    // Now quiesce the other one. This will add a new idle connection, but it
    // won't connect it right away.
    controller.sendGoAwayToChannel(atIndex: 1)
    XCTAssertEqual(pool.sync.connections, 4)
    XCTAssertEqual(pool.sync.idleConnections, 2)
    XCTAssertEqual(pool.sync.activeConnections, 2)
    XCTAssertEqual(pool.sync.transientFailureConnections, 0)
  }
}

extension ConnectionPool {
  // For backwards compatibility, to avoid large diffs in these tests.
  fileprivate func shutdown() -> EventLoopFuture<Void> {
    return self.shutdown(mode: .forceful)
  }
}

// MARK: - Helpers

internal final class ChannelController {
  private var channels: [EmbeddedChannel] = []

  internal var count: Int {
    return self.channels.count
  }

  internal func finish() {
    while let channel = self.channels.popLast() {
      // We're okay with this throwing: some channels are left in a bad state (i.e. with errors).
      _ = try? channel.finish()
    }
  }

  private func isValidIndex(
    _ index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Bool {
    let isValid = self.channels.indices.contains(index)
    XCTAssertTrue(isValid, "Invalid connection index '\(index)'", file: file, line: line)
    return isValid
  }

  internal func connectChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    XCTAssertNoThrow(
      try self.channels[index].connect(to: .init(unixDomainSocketPath: "/")),
      file: file,
      line: line
    )
  }

  internal func fireChannelInactiveForChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }
    self.channels[index].pipeline.fireChannelInactive()
  }

  internal func throwError(
    _ error: Error,
    inChannelAtIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }
    self.channels[index].pipeline.fireErrorCaught(error)
  }

  internal func sendSettingsToChannel(
    atIndex index: Int,
    maxConcurrentStreams: Int = 100,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    let settings = [HTTP2Setting(parameter: .maxConcurrentStreams, value: maxConcurrentStreams)]
    let settingsFrame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings(settings)))

    XCTAssertNoThrow(try self.channels[index].writeInbound(settingsFrame), file: file, line: line)
  }

  internal func sendGoAwayToChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    let goAwayFrame = HTTP2Frame(
      streamID: .rootStream,
      payload: .goAway(lastStreamID: .maxID, errorCode: .noError, opaqueData: nil)
    )

    XCTAssertNoThrow(try self.channels[index].writeInbound(goAwayFrame), file: file, line: line)
  }

  internal func openStreamInChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    // The details don't matter here.
    let event = NIOHTTP2StreamCreatedEvent(
      streamID: .rootStream,
      localInitialWindowSize: nil,
      remoteInitialWindowSize: nil
    )

    self.channels[index].pipeline.fireUserInboundEventTriggered(event)
  }

  internal func closeStreamInChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    // The details don't matter here.
    let event = StreamClosedEvent(streamID: .rootStream, reason: nil)
    self.channels[index].pipeline.fireUserInboundEventTriggered(event)
  }
}

extension ChannelController: ConnectionManagerChannelProvider {
  internal func makeChannel(
    managedBy connectionManager: ConnectionManager,
    onEventLoop eventLoop: EventLoop,
    connectTimeout: TimeAmount?,
    logger: Logger
  ) -> EventLoopFuture<Channel> {
    let channel = EmbeddedChannel(loop: eventLoop as! EmbeddedEventLoop)
    self.channels.append(channel)

    let multiplexer = HTTP2StreamMultiplexer(
      mode: .client,
      channel: channel,
      inboundStreamInitializer: nil
    )

    let idleHandler = GRPCIdleHandler(
      connectionManager: connectionManager,
      multiplexer: multiplexer,
      idleTimeout: .minutes(5),
      keepalive: ClientConnectionKeepalive(),
      logger: logger
    )

    XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(idleHandler))
    XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(multiplexer))

    return eventLoop.makeSucceededFuture(channel)
  }
}

internal struct HookedStreamLender: StreamLender {
  internal var onReturnStreams: (Int) -> Void
  internal var onUpdateMaxAvailableStreams: (Int) -> Void

  internal func returnStreams(_ count: Int, to pool: ConnectionPool) {
    self.onReturnStreams(count)
  }

  internal func changeStreamCapacity(by delta: Int, for: ConnectionPool) {
    self.onUpdateMaxAvailableStreams(delta)
  }
}

extension Optional where Wrapped == GRPCConnectionPoolError {
  internal var isTooManyWaiters: Bool {
    self?.code == .tooManyWaiters
  }

  internal var isDeadlineExceeded: Bool {
    self?.code == .deadlineExceeded
  }

  internal var isShutdown: Bool {
    self?.code == .shutdown
  }
}
