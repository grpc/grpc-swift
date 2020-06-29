/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO
import NIOHTTP2
import XCTest

class ConnectionManagerTests: GRPCTestCase {
  private let loop = EmbeddedEventLoop()
  private let recorder = RecordingConnectivityDelegate()

  private var defaultConfiguration: ClientConnection.Configuration {
    return ClientConnection.Configuration(
      target: .unixDomainSocket("/ignored"),
      eventLoopGroup: self.loop,
      connectivityStateDelegate: self.recorder,
      connectionBackoff: nil
    )
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.loop.syncShutdownGracefully())
    super.tearDown()
  }

  private func waitForStateChange<Result>(
    from: ConnectivityState,
    to: ConnectivityState,
    timeout: DispatchTimeInterval = .seconds(1),
    body: () throws -> Result
  ) rethrows -> Result {
    self.recorder.expectChange {
      XCTAssertEqual($0, Change(from: from, to: to))
    }
    let result = try body()
    self.recorder.waitForExpectedChanges(timeout: timeout)
    return result
  }

  private func waitForStateChanges<Result>(
    _ changes: [Change],
    timeout: DispatchTimeInterval = .seconds(1),
    body: () throws -> Result
  ) rethrows -> Result {
    self.recorder.expectChanges(changes.count) {
      XCTAssertEqual($0, changes)
    }
    let result = try body()
    self.recorder.waitForExpectedChanges(timeout: timeout)
    return result
  }
}

extension ConnectionManagerTests {
  func testIdleShutdown() throws {
    let manager = ConnectionManager(configuration: self.defaultConfiguration, logger: self.logger)

    try self.waitForStateChange(from: .idle, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }

    // Getting a channel should fail.
    let channel = manager.getChannel()
    self.loop.run()
    XCTAssertThrowsError(try channel.wait())
  }

  func testConnectFromIdleFailsWithNoReconnect() {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    let channel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let channel = manager.getChannel()
      self.loop.run()
      return channel
    }

    self.waitForStateChange(from: .connecting, to: .shutdown) {
      channelPromise.fail(DoomedChannelError())
    }

    XCTAssertThrowsError(try channel.wait()) {
      XCTAssertTrue($0 is DoomedChannelError)
    }
  }

  func testConnectAndDisconnect() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    // Start the connection.
    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Setup the real channel and activate it.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a settings frame on the root stream; this'll make the channel 'ready'.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try channel.writeInbound(frame))
    }

    // Close the channel.
    try self.waitForStateChange(from: .ready, to: .shutdown) {
      // Now the channel should be available: shut it down,
      XCTAssertNoThrow(try readyChannel.flatMap { $0.close(mode: .all) }.wait())
    }
  }

  func testConnectAndIdle() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    // Start the connection.
    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Setup the channel.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a settings frame on the root stream; this'll make the channel 'ready'.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try channel.writeInbound(frame))
      // Wait for the channel, it _must_ be ready now.
      XCTAssertNoThrow(try readyChannel.wait())
    }

    // Go idle. This will shutdown the channel.
    try self.waitForStateChange(from: .ready, to: .idle) {
      self.loop.advanceTime(by: .minutes(5))
      XCTAssertNoThrow(try readyChannel.flatMap { $0.closeFuture }.wait())
    }

    // Now shutdown.
    try self.waitForStateChange(from: .idle, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }
  }

  func testIdleTimeoutWhenThereAreActiveStreams() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    // Start the connection.
    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Setup the channel.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a settings frame on the root stream; this'll make the channel 'ready'.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try channel.writeInbound(frame))
      // Wait for the channel, it _must_ be ready now.
      XCTAssertNoThrow(try readyChannel.wait())
    }

    // "create" a stream; the details don't matter here.
    let streamCreated = NIOHTTP2StreamCreatedEvent(
      streamID: 1,
      localInitialWindowSize: nil,
      remoteInitialWindowSize: nil
    )
    channel.pipeline.fireUserInboundEventTriggered(streamCreated)

    // Wait for the idle timeout: this should _not_ cause the channel to idle.
    self.loop.advanceTime(by: .minutes(5))

    // Now we're going to close the stream and wait for an idle timeout and then shutdown.
    self.waitForStateChange(from: .ready, to: .idle) {
      // Close the stream.
      let streamClosed = StreamClosedEvent(streamID: 1, reason: nil)
      channel.pipeline.fireUserInboundEventTriggered(streamClosed)
      // ... wait for the idle timeout,
      self.loop.advanceTime(by: .minutes(5))
    }

    // Now shutdown.
    try self.waitForStateChange(from: .idle, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }
  }

  func testConnectAndThenBecomeInactive() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Setup the channel.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    try self.waitForStateChange(from: .connecting, to: .shutdown) {
      // Okay: now close the channel; the `readyChannel` future has not been completed yet.
      XCTAssertNoThrow(try channel.close(mode: .all).wait())
    }

    // We failed to get a channel and we don't have reconnect configured: we should be shutdown and
    // the `readyChannel` should error.
    XCTAssertThrowsError(try readyChannel.wait())
  }

  func testConnectOnSecondAttempt() throws {
    let channelPromise: EventLoopPromise<Channel> = self.loop.makePromise()
    let channelFutures: [EventLoopFuture<Channel>] = [
      self.loop.makeFailedFuture(DoomedChannelError()),
      channelPromise.futureResult
    ]
    var channelFutureIterator = channelFutures.makeIterator()

    var configuration = self.defaultConfiguration
    configuration.connectionBackoff = .oneSecondFixed

    let manager = ConnectionManager.testingOnly(configuration: configuration, logger: self.logger) {
      guard let next = channelFutureIterator.next() else {
        XCTFail("Too many channels requested")
        return self.loop.makeFailedFuture(DoomedChannelError())
      }
      return next
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChanges([
      Change(from: .idle, to: .connecting),
      Change(from: .connecting, to: .transientFailure)
    ]) {
      // Get a channel.
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Get a channel from the manager: it is a future for the same channel.
    let anotherReadyChannel = manager.getChannel()
    self.loop.run()

    // Move time forwards by a second to start the next connection attempt.
    self.waitForStateChange(from: .transientFailure, to: .connecting) {
      self.loop.advanceTime(by: .seconds(1))
    }

    // Setup the actual channel and complete the promise.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a SETTINGS frame on the root stream.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try channel.writeInbound(frame))
    }

    // Wait for the channel, it _must_ be ready now.
    XCTAssertNoThrow(try readyChannel.wait())
    XCTAssertNoThrow(try anotherReadyChannel.wait())

    // Now shutdown.
    try self.waitForStateChange(from: .ready, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }
  }

  func testShutdownWhileConnecting() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Now shutdown.
    try self.waitForStateChange(from: .connecting, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }

    // The channel we were requesting should fail.
    XCTAssertThrowsError(try readyChannel.wait())

    // We still have our channel promise to fulfil: if it succeeds then it too should be closed.
    channelPromise.succeed(EmbeddedChannel(loop: self.loop))
    let channel = try channelPromise.futureResult.wait()
    self.loop.run()
    XCTAssertNoThrow(try channel.closeFuture.wait())
  }

  func testShutdownWhileTransientFailure() throws {
    var configuration = self.defaultConfiguration
    configuration.connectionBackoff = .oneSecondFixed

    let manager = ConnectionManager.testingOnly(configuration: configuration, logger: self.logger) {
      return self.loop.makeFailedFuture(DoomedChannelError())
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChanges([
      Change(from: .idle, to: .connecting),
      Change(from: .connecting, to: .transientFailure)
    ]) {
      // Get a channel.
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Now shutdown.
    try self.waitForStateChange(from: .transientFailure, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }

    // The channel we were requesting should fail.
    XCTAssertThrowsError(try readyChannel.wait())
  }

  func testShutdownWhileActive() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Prepare the channel
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // (No state change expected here: active is an internal state.)

    // Now shutdown.
    try self.waitForStateChange(from: .connecting, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }

    // The channel we were requesting should fail.
    XCTAssertThrowsError(try readyChannel.wait())
  }

  func testShutdownWhileShutdown() throws {
    let manager = ConnectionManager(configuration: self.defaultConfiguration, logger: self.logger)

    try self.waitForStateChange(from: .idle, to: .shutdown) {
      let firstShutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try firstShutdown.wait())
    }

    let secondShutdown = manager.shutdown()
    self.loop.run()
    XCTAssertNoThrow(try secondShutdown.wait())
  }

  func testTransientFailureWhileActive() throws {
    var configuration = self.defaultConfiguration
    configuration.connectionBackoff = .oneSecondFixed

    let channelPromise: EventLoopPromise<Channel> = self.loop.makePromise()
    let channelFutures: [EventLoopFuture<Channel>] = [
      channelPromise.futureResult,
      self.loop.makeFailedFuture(DoomedChannelError())
    ]
    var channelFutureIterator = channelFutures.makeIterator()

    let manager = ConnectionManager.testingOnly(configuration: configuration, logger: self.logger) {
      guard let next = channelFutureIterator.next() else {
        XCTFail("Too many channels requested")
        return self.loop.makeFailedFuture(DoomedChannelError())
      }
      return next
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Prepare the channel
    let firstChannel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(firstChannel)
    XCTAssertNoThrow(try firstChannel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // (No state change expected here: active is an internal state.)

    // Close the channel (simulate e.g. TLS handshake failed)
    try self.waitForStateChange(from: .connecting, to: .transientFailure) {
      XCTAssertNoThrow(try firstChannel.close().wait())
    }

    // Start connecting again.
    self.waitForStateChanges([
      Change(from: .transientFailure, to: .connecting),
      Change(from: .connecting, to: .transientFailure)
    ]) {
      self.loop.advanceTime(by: .seconds(1))
    }

    // Now shutdown
    try self.waitForStateChange(from: .transientFailure, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }

    // The channel never came up: it should be throw.
    XCTAssertThrowsError(try readyChannel.wait())
  }

  func testTransientFailureWhileReady() throws {
    var configuration = self.defaultConfiguration
    configuration.connectionBackoff = .oneSecondFixed

    let firstChannelPromise: EventLoopPromise<Channel> = self.loop.makePromise()
    let secondChannelPromise: EventLoopPromise<Channel> = self.loop.makePromise()
    let channelFutures: [EventLoopFuture<Channel>] = [
      firstChannelPromise.futureResult,
      secondChannelPromise.futureResult
    ]
    var channelFutureIterator = channelFutures.makeIterator()

    let manager = ConnectionManager.testingOnly(configuration: configuration, logger: self.logger) {
      guard let next = channelFutureIterator.next() else {
        XCTFail("Too many channels requested")
        return self.loop.makeFailedFuture(DoomedChannelError())
      }
      return next
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Prepare the first channel
    let firstChannel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    firstChannelPromise.succeed(firstChannel)
    XCTAssertNoThrow(try firstChannel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a SETTINGS frame on the root stream.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try firstChannel.writeInbound(frame))
    }

    // Channel should now be ready.
    XCTAssertNoThrow(try readyChannel.wait())

    // Kill the first channel.
    try self.waitForStateChange(from: .ready, to: .transientFailure) {
      XCTAssertNoThrow(try firstChannel.close().wait())
    }

    // Run to start connecting again.
    self.waitForStateChange(from: .transientFailure, to: .connecting) {
      self.loop.advanceTime(by: .seconds(1))
    }

    // Prepare the second channel
    let secondChannel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    secondChannelPromise.succeed(secondChannel)
    XCTAssertNoThrow(try secondChannel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    // Write a SETTINGS frame on the root stream.
    try self.waitForStateChange(from: .connecting, to: .ready) {
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try secondChannel.writeInbound(frame))
    }

    // Now shutdown
    try self.waitForStateChange(from: .ready, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }
  }

  func testGoAwayWhenReady() throws {
    let channelPromise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return channelPromise.futureResult
    }

    let readyChannel: EventLoopFuture<Channel> = self.waitForStateChange(from: .idle, to: .connecting) {
      let readyChannel = manager.getChannel()
      self.loop.run()
      return readyChannel
    }

    // Setup the channel.
    let channel = EmbeddedChannel(
      handler: GRPCIdleHandler(mode: .client(manager)),
      loop: self.loop
    )
    channelPromise.succeed(channel)
    XCTAssertNoThrow(try channel.connect(to: SocketAddress(unixDomainSocketPath: "/ignored")).wait())

    try self.waitForStateChange(from: .connecting, to: .ready) {
      // Write a SETTINGS frame on the root stream.
      let frame = HTTP2Frame(streamID: .rootStream, payload: .settings(.settings([])))
      XCTAssertNoThrow(try channel.writeInbound(frame))
    }

    // Wait for the channel, it _must_ be ready now.
    XCTAssertNoThrow(try readyChannel.wait())

    // Send a GO_AWAY; the details don't matter. This will cause the connection to go idle and the
    // channel to close.
    try self.waitForStateChange(from: .ready, to: .idle) {
      let goAway = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: 1, errorCode: .noError, opaqueData: nil)
      )
      XCTAssertNoThrow(try channel.writeInbound(goAway))
    }

    self.loop.run()
    XCTAssertNoThrow(try channel.closeFuture.wait())

    // Now shutdown
    try self.waitForStateChange(from: .idle, to: .shutdown) {
      let shutdown = manager.shutdown()
      self.loop.run()
      XCTAssertNoThrow(try shutdown.wait())
    }
  }

  func testDoomedOptimisticChannelFromIdle() {
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return self.loop.makeFailedFuture(DoomedChannelError())
    }
    let candidate = manager.getOptimisticChannel()
    self.loop.run()
    XCTAssertThrowsError(try candidate.wait())
  }

  func testDoomedOptimisticChannelFromConnecting() throws {
    let promise = self.loop.makePromise(of: Channel.self)
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return promise.futureResult
    }

    self.waitForStateChange(from: .idle, to: .connecting) {
      // Trigger channel creation, and a connection attempt, we don't care about the channel.
      _ = manager.getChannel()
      self.loop.run()
    }

    // We're connecting: get an optimistic channel.
    let optimisticChannel = manager.getOptimisticChannel()
    self.loop.run()

    // Fail the promise.
    promise.fail(DoomedChannelError())

    XCTAssertThrowsError(try optimisticChannel.wait())
  }

  func testOptimisticChannelFromTransientFailure() throws {
    var configuration = self.defaultConfiguration
    configuration.connectionBackoff = ConnectionBackoff()

    let manager = ConnectionManager.testingOnly(configuration: configuration, logger: self.logger) {
      return self.loop.makeFailedFuture(DoomedChannelError())
    }

    self.waitForStateChanges([
      Change(from: .idle, to: .connecting),
      Change(from: .connecting, to: .transientFailure)
    ]) {
      // Trigger channel creation, and a connection attempt, we don't care about the channel.
      _ = manager.getChannel()
      self.loop.run()
    }

    // Now we're sitting in transient failure. Get a channel optimistically.
    let optimisticChannel = manager.getOptimisticChannel()
    self.loop.run()

    XCTAssertThrowsError(try optimisticChannel.wait())
  }

  func testOptimisticChannelFromShutdown() throws {
    let manager = ConnectionManager.testingOnly(configuration: self.defaultConfiguration, logger: self.logger) {
      return self.loop.makeFailedFuture(DoomedChannelError())
    }

    let shutdown = manager.shutdown()
    self.loop.run()
    XCTAssertNoThrow(try shutdown.wait())

    // Get a channel optimistically. It'll fail, obviously.
    let channel = manager.getOptimisticChannel()
    self.loop.run()
    XCTAssertThrowsError(try channel.wait())
  }
}

internal struct Change: Hashable, CustomStringConvertible {
  var from: ConnectivityState
  var to: ConnectivityState

  var description: String {
    return "\(self.from) → \(self.to)"
  }
}

internal class RecordingConnectivityDelegate: ConnectivityStateDelegate {
  private let serialQueue = DispatchQueue(label: "io.grpc.testing")
  private let semaphore = DispatchSemaphore(value: 0)
  private var expectation: Expectation = .noExpectation

  private enum Expectation {
    /// We have no expectation of any changes. We'll just ignore any changes.
    case noExpectation

    /// We expect one change.
    case one((Change) -> ())

    /// We expect 'count' changes.
    case some(count: Int, recorded: [Change], ([Change]) -> ())

    var count: Int {
      switch self {
      case .noExpectation:
        return 0
      case .one:
        return 1
      case .some(let count, _, _):
        return count
      }
    }
  }

  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
    self.serialQueue.async {
      switch self.expectation {
      case .one(let verify):
        // We don't care about future changes.
        self.expectation = .noExpectation

        // Verify and notify.
        verify(Change(from: oldState, to: newState))
        self.semaphore.signal()

      case .some(let count, var recorded, let verify):
        recorded.append(Change(from: oldState, to: newState))
        if recorded.count == count {
          // We don't care about future changes.
          self.expectation = .noExpectation

          // Verify and notify.
          verify(recorded)
          self.semaphore.signal()
        } else {
          // Still need more responses.
          self.expectation = .some(count: count, recorded: recorded, verify)
        }

      case .noExpectation:
        // Ignore any changes.
        ()
      }
    }
  }

  func expectChanges(_ count: Int, verify: @escaping ([Change]) -> ()) {
    self.serialQueue.async {
      self.expectation = .some(count: count, recorded: [], verify)
    }
  }

  func expectChange(verify: @escaping (Change) -> ()) {
    self.serialQueue.async {
      self.expectation = .one(verify)
    }
  }

  func waitForExpectedChanges(timeout: DispatchTimeInterval) {
    let result = self.semaphore.wait(timeout: .now() + timeout)
    switch result {
    case .success:
      ()
    case .timedOut:
      XCTFail("Timed out before verifying \(self.expectation.count) change(s)")
    }
  }
}

fileprivate extension ConnectionBackoff {
  static let oneSecondFixed = ConnectionBackoff(
    initialBackoff: 1.0,
    maximumBackoff: 1.0,
    multiplier: 1.0,
    jitter: 0.0
  )
}

fileprivate struct DoomedChannelError: Error {}
