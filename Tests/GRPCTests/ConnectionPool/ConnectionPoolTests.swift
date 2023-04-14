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
@testable import GRPC
import Logging
import NIOCore
import NIOEmbedded
import NIOHTTP2
import XCTest

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
      reservationLoadThreshold: reservationLoadThreshold,
      assumedMaxConcurrentStreams: 100,
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
      XCTAssert((error as? ConnectionPoolError).isShutdown)
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
      XCTAssert((error as? ConnectionPoolError).isTooManyWaiters)
    }

    XCTAssertNoThrow(try pool.shutdown().wait())
    // All 'waiting' futures will be failed by the shutdown promise.
    for waiter in waiting {
      XCTAssertThrowsError(try waiter.wait()) { error in
        XCTAssert((error as? ConnectionPoolError).isShutdown)
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
      XCTAssert((error as? ConnectionPoolError).isDeadlineExceeded)
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
      XCTAssert((error as? ConnectionPoolError).isDeadlineExceeded)
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
        XCTAssert((error as? ConnectionPoolError).isShutdown)
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
      XCTAssert((error as? ConnectionPoolError).isDeadlineExceeded)
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
      switch error as? ConnectionPoolError {
      case .some(.deadlineExceeded(.none)):
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
      switch error as? ConnectionPoolError {
      case let .some(.deadlineExceeded(.some(wrappedError))):
        // Deadline exceeded and we have the underlying error.
        XCTAssert(wrappedError is DummyError)
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
      switch error as? ConnectionPoolError {
      case .some(.tooManyWaiters(.none)):
        ()
      default:
        XCTFail("Expected ConnectionPoolError.tooManyWaiters(.none) but got \(error)")
      }
    }

    // Finally, timeout the remaining waiters. Again, no inner error, the connection is just busy.
    self.eventLoop.advanceTime(by: .seconds(1))
    for waiter in waiters {
      XCTAssertThrowsError(try waiter.wait()) { error in
        switch error as? ConnectionPoolError {
        case .some(.deadlineExceeded(.none)):
          ()
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
      waiter.fail(ConnectionPoolError.deadlineExceeded(connectionError: nil))
    }

    XCTAssertNotNil(waiter._scheduledTimeout)
    self.eventLoop.advanceTime(to: deadline)
    XCTAssertThrowsError(try promise.futureResult.wait())
    XCTAssertNil(waiter._scheduledTimeout)
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
}

extension ConnectionPool {
  // For backwards compatibility, to avoid large diffs in these tests.
  fileprivate func shutdown() -> EventLoopFuture<Void> {
    return self.shutdown(mode: .forceful)
  }
}

// MARK: - Helpers

struct ChannelAndState {
  let channel: EmbeddedChannel
  let streamDelegate: NIOHTTP2StreamDelegate
  var isActive: Bool
}

internal final class ChannelController {
  private var channels: [ChannelAndState] = []

  internal var count: Int {
    return self.channels.count
  }

  internal func finish() {
    while let state = self.channels.popLast() {
      if state.isActive {
        _ = try? state.channel.finish()
      }
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
    self.channels[index].isActive = true

    XCTAssertNoThrow(
      try self.channels[index].channel.connect(to: .init(unixDomainSocketPath: "/")),
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
    self.channels[index].channel.pipeline.fireChannelInactive()
    self.channels[index].isActive = false
  }

  internal func throwError(
    _ error: Error,
    inChannelAtIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }
    self.channels[index].channel.pipeline.fireErrorCaught(error)
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

    XCTAssertNoThrow(
      try self.channels[index].channel.writeInbound(settingsFrame.encode()),
      file: file,
      line: line
    )
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

    XCTAssertNoThrow(
      try self.channels[index].channel.writeInbound(goAwayFrame.encode()),
      file: file,
      line: line
    )
  }

  internal func openStreamInChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    // The details don't matter here.
    let channel = self.channels[index]
    channel.streamDelegate.streamCreated(.rootStream, channel: channel.channel)
  }

  internal func closeStreamInChannel(
    atIndex index: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    // The details don't matter here.
    let channel = self.channels[index]
    channel.streamDelegate.streamClosed(.rootStream, channel: channel.channel)
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

    let idleHandler = GRPCIdleHandler(
      connectionManager: connectionManager,
      idleTimeout: .minutes(5),
      keepalive: ClientConnectionKeepalive(),
      logger: logger
    )

    let h2handler = NIOHTTP2Handler(
      mode: .client,
      eventLoop: channel.eventLoop,
      streamDelegate: idleHandler
    ) { channel in
      channel.eventLoop.makeSucceededVoidFuture()
    }
    XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(h2handler))

    idleHandler.setMultiplexer(try! h2handler.syncMultiplexer())
    self.channels.append(.init(channel: channel, streamDelegate: idleHandler, isActive: false))

    XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(idleHandler))

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

extension Optional where Wrapped == ConnectionPoolError {
  internal var isTooManyWaiters: Bool {
    switch self {
    case .some(.tooManyWaiters):
      return true
    case .some(.deadlineExceeded), .some(.shutdown), .none:
      return false
    }
  }

  internal var isDeadlineExceeded: Bool {
    switch self {
    case .some(.deadlineExceeded):
      return true
    case .some(.tooManyWaiters), .some(.shutdown), .none:
      return false
    }
  }

  internal var isShutdown: Bool {
    switch self {
    case .some(.shutdown):
      return true
    case .some(.tooManyWaiters), .some(.deadlineExceeded), .none:
      return false
    }
  }
}

// Simplified version of the frame encoder found in SwiftNIO HTTP/2
struct HTTP2FrameEncoder {
  mutating func encode(frame: HTTP2Frame, to buf: inout ByteBuffer) throws -> IOData? {
    // note our starting point
    let start = buf.writerIndex

    //      +-----------------------------------------------+
    //      |                 Length (24)                   |
    //      +---------------+---------------+---------------+
    //      |   Type (8)    |   Flags (8)   |
    //      +-+-------------+---------------+-------------------------------+
    //      |R|                 Stream Identifier (31)                      |
    //      +=+=============================================================+
    //      |                   Frame Payload (0...)                      ...
    //      +---------------------------------------------------------------+

    // skip 24-bit length for now, we'll fill that in later
    buf.moveWriterIndex(forwardBy: 3)

    // 8-bit type
    buf.writeInteger(frame.code())

    // skip the 8 bit flags for now, we'll fill it in later as well.
    let flagsIndex = buf.writerIndex
    var flags = FrameFlags()
    buf.moveWriterIndex(forwardBy: 1)

    // 32-bit stream identifier -- ensuring the top bit is empty
    buf.writeInteger(Int32(frame.streamID))

    // frame payload follows, which depends on the frame type itself
    let payloadStart = buf.writerIndex
    let extraFrameData: IOData?
    let payloadSize: Int

    switch frame.payload {
    case let .settings(.settings(settings)):
      for setting in settings {
        buf.writeInteger(setting.parameter.networkRepresentation())
        buf.writeInteger(UInt32(setting.value))
      }

      payloadSize = settings.count * 6
      extraFrameData = nil

    case .settings(.ack):
      payloadSize = 0
      extraFrameData = nil
      flags.insert(.ack)

    case let .goAway(lastStreamID, errorCode, opaqueData):
      let streamVal = UInt32(Int(lastStreamID)) & ~0x8000_0000
      buf.writeInteger(streamVal)
      buf.writeInteger(UInt32(errorCode.networkCode))

      if let data = opaqueData {
        payloadSize = data.readableBytes + 8
        extraFrameData = .byteBuffer(data)
      } else {
        payloadSize = 8
        extraFrameData = nil
      }

    case .data, .headers, .priority,
         .rstStream, .pushPromise, .ping,
         .windowUpdate, .alternativeService, .origin:
      preconditionFailure("Frame type not supported: \(frame.payload)")
    }

    // Write the frame data. This is the payload size and the flags byte.
    buf.writePayloadSize(payloadSize, at: start)
    buf.setInteger(flags.rawValue, at: flagsIndex)

    // all bytes to write are in the provided buffer now
    return extraFrameData
  }

  struct FrameFlags: OptionSet {
    internal private(set) var rawValue: UInt8

    internal init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// ACK flag. Valid on SETTINGS and PING frames.
    internal static let ack = FrameFlags(rawValue: 0x01)
  }
}

extension HTTP2SettingsParameter {
  internal func networkRepresentation() -> UInt16 {
    switch self {
    case HTTP2SettingsParameter.headerTableSize:
      return UInt16(1)
    case HTTP2SettingsParameter.enablePush:
      return UInt16(2)
    case HTTP2SettingsParameter.maxConcurrentStreams:
      return UInt16(3)
    case HTTP2SettingsParameter.initialWindowSize:
      return UInt16(4)
    case HTTP2SettingsParameter.maxFrameSize:
      return UInt16(5)
    case HTTP2SettingsParameter.maxHeaderListSize:
      return UInt16(6)
    case HTTP2SettingsParameter.enableConnectProtocol:
      return UInt16(8)
    default:
      preconditionFailure("Unknown settings parameter.")
    }
  }
}

extension ByteBuffer {
  fileprivate mutating func writePayloadSize(_ size: Int, at location: Int) {
    // Yes, this performs better than running a UInt8 through the generic write(integer:) three times.
    var bytes: (UInt8, UInt8, UInt8)
    bytes.0 = UInt8((size & 0xFF0000) >> 16)
    bytes.1 = UInt8((size & 0x00FF00) >> 8)
    bytes.2 = UInt8(size & 0x0000FF)
    withUnsafeBytes(of: bytes) { ptr in
      _ = self.setBytes(ptr, at: location)
    }
  }
}

extension HTTP2Frame {
  internal func encode() throws -> ByteBuffer {
    let allocator = ByteBufferAllocator()
    var buffer = allocator.buffer(capacity: 1024)

    var frameEncoder = HTTP2FrameEncoder()
    let extraData = try frameEncoder.encode(frame: self, to: &buffer)
    if let extraData = extraData {
      switch extraData {
      case let .byteBuffer(extraBuffer):
        buffer.writeImmutableBuffer(extraBuffer)
      default:
        preconditionFailure()
      }
    }
    return buffer
  }

  /// The one-byte identifier used to indicate the type of a frame on the wire.
  internal func code() -> UInt8 {
    switch self.payload {
    case .data: return 0x0
    case .headers: return 0x1
    case .priority: return 0x2
    case .rstStream: return 0x3
    case .settings: return 0x4
    case .pushPromise: return 0x5
    case .ping: return 0x6
    case .goAway: return 0x7
    case .windowUpdate: return 0x8
    case .alternativeService: return 0xA
    case .origin: return 0xC
    }
  }
}
