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
import EchoImplementation
import EchoModel
@testable import GRPC
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOHPACK
import NIOHTTP2
import XCTest

final class ConnectionPoolTests: GRPCTestCase {
  private let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  private var server: Server!
  private var clientGroup: EventLoopGroup!
  private var pool: ConnectionPool!

  override func setUp() {
    super.setUp()

    self.server = try! Server.insecure(group: self.serverGroup)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  private func setUpPool(
    numberOfThreads: Int,
    maxConnections: Int,
    bringUpThreshold: Int = 10,
    maximumConnectionWaiters: Int = 100
  ) {
    self.clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    self.pool = ConnectionPool(
      target: .hostAndPort("127.0.0.1", self.server.channel.localAddress!.port!),
      group: self.clientGroup,
      maximumConnections: maxConnections,
      maximumConnectionWaitTime: .minutes(1), // we don't rely on the default in tests
      maximumConnectionWaiters: maximumConnectionWaiters,
      nextConnectionThreshold: bringUpThreshold,
      logger: self.clientLogger
    )
  }

  override func tearDown() {
    let shutdownPromise = self.clientGroup.next().makePromise(of: Void.self)
    self.pool.shutdown(promise: shutdownPromise)
    XCTAssertNoThrow(try shutdownPromise.futureResult.wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.clientGroup.syncShutdownGracefully())
    XCTAssertNoThrow(try self.serverGroup.syncShutdownGracefully())
  }

  func testShutdownIdlePool() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)
    let eventLoop = self.clientGroup.next()
    XCTAssertEqual(self.pool.readyCount, 0)
    XCTAssertEqual(self.pool.connectingCount, 0)
    XCTAssertEqual(self.pool.idleCount, 1)

    let promise = eventLoop.makePromise(of: Void.self)
    self.pool.shutdown(promise: promise)
    XCTAssertNoThrow(try promise.futureResult.wait())
  }

  func testShutdownIsIdempotent() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)
    let eventLoop = self.clientGroup.next()

    // Make sure we spin up a connection.
    let multiplexer = self.pool.waitForMultiplexer(eventLoop: eventLoop)
    XCTAssertNoThrow(try multiplexer.wait())
    XCTAssertEqual(self.pool.readyCount, 1)

    let promises = (0 ..< 100).map { _ in eventLoop.makePromise(of: Void.self) }
    for promise in promises {
      self.pool.shutdown(promise: promise)
    }

    let shutdown = EventLoopFuture.andAllSucceed(promises.map { $0.futureResult }, on: eventLoop)
    XCTAssertNoThrow(try shutdown.wait())
  }

  func testShutdownDoesNotProvideMultiplexers() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)
    let eventLoop = self.clientGroup.next()
    let promise = eventLoop.makePromise(of: Void.self)

    // 1 idle connection in the pool.
    XCTAssertEqual(self.pool.count, 1)
    XCTAssertEqual(self.pool.idleCount, 1)

    self.pool.shutdown(promise: promise)
    XCTAssertNoThrow(try promise.futureResult.wait())

    XCTAssertNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))

    let multiplexer = self.pool.waitForMultiplexer(eventLoop: eventLoop)
    XCTAssertThrowsError(try multiplexer.wait()) { error in
      XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
    }

    // No connections in the pool.
    XCTAssertEqual(self.pool.count, 0)
  }

  func testShutdownFailsWaiters() throws {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)
    let eventLoop = self.clientGroup.next()

    // Ensure we have a ready connection.
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait())
    XCTAssertEqual(self.pool.readyCount, 1)

    while self.pool.availableHTTP2Streams > 0 {
      XCTAssertNotNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))
    }

    // We used all available streams.
    XCTAssertEqual(self.pool.availableHTTP2Streams, 0)

    // Enqueue some waiters.
    let waiters = (0 ..< 100).map { _ in
      self.pool.waitForMultiplexer(eventLoop: eventLoop)
    }

    // Shutdown.
    let shutdownPromise = eventLoop.makePromise(of: Void.self)
    self.pool.shutdown(promise: shutdownPromise)
    XCTAssertNoThrow(try shutdownPromise.futureResult.wait())

    // Pool is shutdown, the waiters should not succeed.
    let results = try EventLoopFuture.whenAllComplete(waiters, on: eventLoop).wait()

    for result in results {
      switch result {
      case .success:
        XCTFail("Unexpected success")
      case let .failure(error):
        XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
      }
    }
  }

  func testPoolWith1Connection() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    XCTAssertEqual(self.pool.count, 1)
    XCTAssertEqual(self.pool.idleCount, 1)
    XCTAssertEqual(self.pool.readyCount, 0)
    XCTAssertEqual(self.pool.connectingCount, 0)
    XCTAssertEqual(self.pool.availableHTTP2Streams, 0)
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 0)

    // No connections are ready or have available streams.
    XCTAssertNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))

    let eventLoop = self.clientGroup.next()
    let multiplexer = self.pool.waitForMultiplexer(eventLoop: eventLoop)

    // Connection should be underway.
    XCTAssertEqual(self.pool.idleCount, 0)
    XCTAssertEqual(self.pool.connectingCount + self.pool.readyCount, 1)

    // This will eventually resolve.
    XCTAssertNoThrow(try multiplexer.wait())
    XCTAssertEqual(self.pool.readyCount, 1)
    XCTAssertGreaterThan(self.pool.availableHTTP2Streams, 0)
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)

    // Now there's an active connection this should be fine.
    XCTAssertNotNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 2)
  }

  func testTryGetPreferringEventLoopNotInPool() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)
    let eventLoop = self.clientGroup.next()
    // Make sure there's a ready connection.
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait())
    XCTAssertEqual(self.pool.readyCount, 1)

    // Try getting a multiplexer but prefer an event loop which has nothing to do with the pool.
    let preferredLoop = self.serverGroup.next()
    guard let (_, actualLoop) = self.pool.tryGetMultiplexer(
      preferredEventLoop: preferredLoop
    ) else {
      XCTFail("tryGetMultiplexer(preferredEventLoop:) unexpectedly returned nil")
      return
    }

    // Shouldn't be our preferred loop, that's fine.
    XCTAssertFalse(actualLoop === preferredLoop)
  }

  func testTryGetPreferringEventLoopInPool() {
    self.setUpPool(numberOfThreads: 2, maxConnections: 2, bringUpThreshold: 1)
    let loop1 = self.clientGroup.next()
    let loop2 = self.clientGroup.next()

    // Make sure two connections are ready connection. (The loop here doesn't matter.)
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: loop1).wait())
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: loop1).wait())

    let allReady = loop1.poll(every: .milliseconds(50)) {
      return self.pool.readyCount == 2
    }

    XCTAssertNoThrow(try allReady.wait())

    for _ in 0 ..< 10 {
      if let (_, actual) = self.pool.tryGetMultiplexer(preferredEventLoop: loop1) {
        XCTAssertTrue(actual === loop1)
      } else {
        XCTFail("tryGetMultiplexer(preferredEventLoop:) returned nil")
        return
      }
    }

    for _ in 0 ..< 10 {
      if let (_, actual) = self.pool.tryGetMultiplexer(preferredEventLoop: loop2) {
        XCTAssertTrue(actual === loop2)
      } else {
        XCTFail("tryGetMultiplexer(preferredEventLoop:) returned nil")
        return
      }
    }
  }

  func testWaiterTimesOutImmediately() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    let eventLoop = self.clientGroup.next()
    let multiplexer = self.pool.waitForMultiplexer(eventLoop: eventLoop, until: .now())

    XCTAssertThrowsError(try multiplexer.wait()) { error in
      XCTAssertEqual(error as? ConnectionPoolError, .waiterTimedOut)
    }
  }

  func testWaiterTimesOutAfterSomeTime() {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    let eventLoop = self.clientGroup.next()
    // Bring up a connection.
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait())
    XCTAssertGreaterThan(self.pool.availableHTTP2Streams, 0)

    // Consume the remaining tokens on that connection.
    while self.pool.availableHTTP2Streams > 0 {
      XCTAssertNotNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))
    }

    // Enqueue a waiter; this will time out because there are no available tokens and no capacity
    // for more connections.
    let multiplexer = self.pool.waitForMultiplexer(
      eventLoop: eventLoop,
      until: .now() + .milliseconds(100)
    )

    XCTAssertThrowsError(try multiplexer.wait()) { error in
      XCTAssertEqual(error as? ConnectionPoolError, .waiterTimedOut)
    }
  }

  func testFailImmediatelyOnTooManyWaiters() throws {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1, maximumConnectionWaiters: 5)
    let eventLoop = self.clientGroup.next()

    // Bring up a connection and consume all available streams.
    XCTAssertNoThrow(try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait())
    while self.pool.availableHTTP2Streams > 0 {
      XCTAssertNotNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))
    }

    // Enqueue 5 waiters, that's the maximum we set above. These will all wait because we won't
    // return any the streams we consumed.
    let futures: [EventLoopFuture<HTTP2StreamMultiplexer>] = (0 ..< 5).map { _ in
      self.pool.waitForMultiplexer(eventLoop: eventLoop)
    }

    // Enqueue another waiter: it should fail quickly.
    XCTAssertThrowsError(try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait()) { error in
      XCTAssertEqual(error as? ConnectionPoolError, .tooManyWaiters)
    }

    // Shutdown; this should fail the outstanding waiters.
    let shutdownPromise = eventLoop.makePromise(of: Void.self)
    self.pool.shutdown(promise: shutdownPromise)
    XCTAssertNoThrow(try shutdownPromise.futureResult.wait())

    let allResults = EventLoopFuture.whenAllComplete(futures, on: eventLoop)
    for result in try assertNoThrow(try allResults.wait()) {
      switch result {
      case .success:
        XCTFail("Unexpected success")
      case let .failure(error):
        XCTAssertEqual(error as? ConnectionPoolError, .shutdown)
      }
    }
  }

  private func sendEchoGetHeaders(on channel: Channel) -> EventLoopFuture<Void> {
    let headers: HPACKHeaders = [
      ":method": "POST",
      ":path": "/echo.Echo/Get",
      ":authority": "localhost",
      ":scheme": "http",
      "content-type": "application/grpc",
      "te": "trailers",
    ]

    let headersPayload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
    return channel.writeAndFlush(headersPayload)
  }

  private func sendEmptyData(on channel: Channel, endStream: Bool) -> EventLoopFuture<Void> {
    let dataPayload = HTTP2Frame.FramePayload.data(
      .init(data: .byteBuffer(.init()), endStream: endStream)
    )
    return channel.writeAndFlush(dataPayload)
  }

  private func sendEmptyEchoGet(on channel: Channel) -> EventLoopFuture<Void> {
    return self.sendEchoGetHeaders(on: channel).flatMap {
      return self.sendEmptyData(on: channel, endStream: true)
    }
  }

  func testTokenIsReturned() throws {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    let eventLoop = self.clientGroup.next()
    // Bring up a connection.
    let multiplexer = try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait()
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)

    // We don't have a client so we have to manually construct the RPC.
    let streamPromise = eventLoop.makePromise(of: Channel.self)
    multiplexer.createStreamChannel(promise: streamPromise) { channel in
      return channel.eventLoop.makeSucceededFuture(())
    }

    let stream = try streamPromise.futureResult.wait()
    XCTAssertNoThrow(try self.sendEmptyEchoGet(on: stream).wait())

    // Wait for the stream to be closed, after which the borrowed streams count should have
    // dropped.
    XCTAssertNoThrow(try stream.closeFuture.wait())

    // The close notification to the pool comes via dispatch queue so we'll poll until it's
    // returned.
    let returned = eventLoop.poll(every: .milliseconds(50)) {
      self.pool.borrowedHTTP2Streams == 0
    }
    XCTAssertNoThrow(try returned.wait())
  }

  func testWaiterIsSucceededAfterStreamIsReturned() throws {
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    let eventLoop = self.clientGroup.next()
    // Bring up a connection.
    let multiplexer1 = try self.pool.waitForMultiplexer(eventLoop: eventLoop).wait()
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)
    XCTAssertGreaterThan(self.pool.availableHTTP2Streams, 0)

    // We don't have a client so we have to manually construct the RPC.
    let streamPromise = eventLoop.makePromise(of: Channel.self)
    multiplexer1.createStreamChannel(promise: streamPromise) { channel in
      return channel.eventLoop.makeSucceededFuture(())
    }

    // Only send headers so the RPC doesn't complete.
    let stream = try streamPromise.futureResult.wait()
    XCTAssertNoThrow(try self.sendEchoGetHeaders(on: stream).wait())
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)

    // Enqueue a waiter. The 'normal' flow would be to try first and then enqueue a waiter, as such
    // enqueue a waiter won't look at available capacity.
    let multiplexer2Future = self.pool.waitForMultiplexer(eventLoop: eventLoop)
    multiplexer2Future.whenComplete { result in
      switch result {
      case .success:
        // Should be 1 because we got this as a result of the other stream being returned.
        XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)
      case let .failure(error):
        XCTFail("Failed to get multiplexer: \(error)")
      }
    }

    // Finish the other RPC.
    XCTAssertNoThrow(try self.sendEmptyData(on: stream, endStream: true).wait())

    // Now the multiplexer future should complete.
    XCTAssertNoThrow(try multiplexer2Future.wait())
  }

  func testPoolWith2Connections() {
    let bringUpThreshold = 5
    self.setUpPool(numberOfThreads: 1, maxConnections: 2, bringUpThreshold: bringUpThreshold)
    let eventLoop = self.clientGroup.next()

    XCTAssertEqual(self.pool.count, 2)
    XCTAssertEqual(self.pool.idleCount, 2)

    let multiplexer = self.pool.waitForMultiplexer(eventLoop: eventLoop)
    XCTAssertNoThrow(try multiplexer.wait())

    XCTAssertEqual(self.pool.idleCount, 1)
    XCTAssertEqual(self.pool.readyCount, 1)
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, 1)

    // Add back the borrowed streams.
    let availableFor1Connection = self.pool.availableHTTP2Streams + self.pool.borrowedHTTP2Streams

    // Get a multiplexer, but only if we don't have to wait (i.e. make sure we use the ready
    // connection). Stop so we hit the bring up threshold.
    for _ in 0 ..< (bringUpThreshold - 1) {
      XCTAssertEqual(self.pool.readyCount, 1)
      XCTAssertNotNil(self.pool.tryGetMultiplexer(preferredEventLoop: nil))
    }

    // We hit the bring-up threshold, there shouldn't be any idle connections now.
    XCTAssertEqual(self.pool.borrowedHTTP2Streams, bringUpThreshold)
    XCTAssertEqual(self.pool.idleCount, 0)

    let twoConnectionsAreReady = eventLoop.poll(every: .milliseconds(5)) {
      return self.pool.readyCount == 2
    }

    XCTAssertNoThrow(try twoConnectionsAreReady.wait())
    // 2 connections are ready: there should be move streams available.
    let availableFor2Connections = self.pool.availableHTTP2Streams + self.pool.borrowedHTTP2Streams
    XCTAssertGreaterThan(availableFor2Connections, availableFor1Connection)
  }

  func testErrors() {
    // (tearDown relies on this being called.)
    self.setUpPool(numberOfThreads: 1, maxConnections: 1)

    XCTAssertEqual(ConnectionPoolError.shutdown.makeGRPCStatus().code, .unavailable)
    XCTAssertEqual(ConnectionPoolError.waiterTimedOut.makeGRPCStatus().code, .unavailable)
    XCTAssertEqual(ConnectionPoolError.tooManyWaiters.makeGRPCStatus().code, .unavailable)
  }
}

extension EventLoop {
  internal func poll(
    after initialDelay: TimeAmount = .zero,
    every delay: TimeAmount,
    until predicate: @escaping () -> Bool
  ) -> EventLoopFuture<Void> {
    let completed = self.makePromise(of: Void.self)

    self.scheduleRepeatedTask(initialDelay: initialDelay, delay: delay, notifying: completed) {
      print("waiting ... ")
      if predicate() {
        $0.cancel()
      }
    }

    return completed.futureResult
  }
}

extension ConnectionPool {
  internal func waitForMultiplexer(
    eventLoop: EventLoop,
    until deadline: NIODeadline? = nil
  ) -> EventLoopFuture<HTTP2StreamMultiplexer> {
    let promise = eventLoop.makePromise(of: HTTP2StreamMultiplexer.self)
    self.waitForMultiplexer(promise: promise, until: deadline)
    return promise.futureResult
  }
}
