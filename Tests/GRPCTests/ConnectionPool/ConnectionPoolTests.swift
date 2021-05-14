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
import NIO
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
    onReservationReturned: @escaping (Int) -> Void = { _ in },
    onMaximumReservationsChange: @escaping (Int) -> Void = { _ in },
    channelProvider: ConnectionManagerChannelProvider
  ) -> ConnectionPool {
    return ConnectionPool(
      eventLoop: self.eventLoop,
      maxWaiters: waiters,
      reservationLoadThreshold: reservationLoadThreshold,
      assumedMaxConcurrentStreams: 100,
      channelProvider: channelProvider,
      streamLender: HookedStreamLender(
        onReturnStreams: onReservationReturned,
        onUpdateMaxAvailableStreams: onMaximumReservationsChange
      ),
      logger: self.logger.wrapped,
      now: now
    )
  }

  private func makePool(
    waiters: Int = 1000,
    makeChannel: @escaping (ConnectionManager, EventLoop) -> EventLoopFuture<Channel>
  ) -> ConnectionPool {
    return self.makePool(
      waiters: waiters,
      channelProvider: HookedChannelProvider(makeChannel)
    )
  }

  private func setUpPoolAndController(
    waiters: Int = 1000,
    reservationLoadThreshold: Double = 0.9,
    now: @escaping () -> NIODeadline = { .now() },
    onReservationReturned: @escaping (Int) -> Void = { _ in },
    onMaximumReservationsChange: @escaping (Int) -> Void = { _ in }
  ) -> (ConnectionPool, ChannelController) {
    let controller = ChannelController()
    let pool = self.makePool(
      waiters: waiters,
      reservationLoadThreshold: reservationLoadThreshold,
      now: now,
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

    XCTAssertNoThrow(try pool.shutdown().wait())
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
      XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
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
      XCTAssertEqual(error as? ConnectionPoolError, .tooManyWaiters)
    }

    XCTAssertNoThrow(try pool.shutdown().wait())
    // All 'waiting' futures will be failed by the shutdown promise.
    for waiter in waiting {
      XCTAssertThrowsError(try waiter.wait()) { error in
        XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
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
      XCTAssertEqual(error as? ConnectionPoolError, .deadlineExceeded)
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
      XCTAssertEqual(error as? ConnectionPoolError, .deadlineExceeded)
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
        XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
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
      XCTAssertEqual(error as? ConnectionPoolError, .deadlineExceeded)
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
    XCTAssertEqual(pool.sync.reservedStreams, 0)
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

    XCTAssertEqual(pool.sync.reservedStreams, 1)
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
    file: StaticString = #file,
    line: UInt = #line
  ) -> Bool {
    let isValid = self.channels.indices.contains(index)
    XCTAssertTrue(isValid, "Invalid connection index '\(index)'", file: file, line: line)
    return isValid
  }

  internal func connectChannel(
    atIndex index: Int,
    file: StaticString = #file,
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
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }
    self.channels[index].pipeline.fireChannelInactive()
  }

  internal func throwError(
    _ error: Error,
    inChannelAtIndex index: Int,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }
    self.channels[index].pipeline.fireErrorCaught(error)
  }

  internal func sendSettingsToChannel(
    atIndex index: Int,
    maxConcurrentStreams: Int = 100,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard self.isValidIndex(index, file: file, line: line) else { return }

    let settings = [HTTP2Setting(parameter: .maxConcurrentStreams, value: maxConcurrentStreams)]
    let settingsFrame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings(settings)))

    XCTAssertNoThrow(try self.channels[index].writeInbound(settingsFrame), file: file, line: line)
  }

  internal func sendGoAwayToChannel(
    atIndex index: Int,
    file: StaticString = #file,
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
    file: StaticString = #file,
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
    file: StaticString = #file,
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

  internal func increaseStreamCapacity(by max: Int, for pool: ConnectionPool) {
    self.onUpdateMaxAvailableStreams(max)
  }
}
