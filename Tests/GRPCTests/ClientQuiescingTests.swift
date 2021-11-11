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
import EchoImplementation
import EchoModel
import GRPC
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

internal final class ClientQuiescingTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var channel: GRPCChannel!
  private var server: Server!
  private let tracker = RPCTracker()

  private var echo: Echo_EchoClient {
    return Echo_EchoClient(channel: self.channel)
  }

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    self.server = try! Server.insecure(group: self.group)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .bind(host: "127.0.0.1", port: 1234)
      .wait()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    // We don't shutdown the client: it will have been shutdown by the test case.
    super.tearDown()
  }

  private func setUpClientConnection() {
    self.channel = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: self.server!.channel.localAddress!.port!)
  }

  private func setUpChannelPool(useSingleEventLoop: Bool = false) {
    // Only throws for TLS which we aren't using here.
    self.channel = try! GRPCChannelPool.with(
      target: .host("127.0.0.1", port: self.server!.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: useSingleEventLoop ? self.group.next() : self.group
    ) {
      $0.connectionPool.connectionsPerEventLoop = 1
      $0.connectionPool.maxWaitersPerEventLoop = 100
      $0.backgroundActivityLogger = self.clientLogger
    }
  }

  private enum ChannelKind {
    case single
    case pooled
  }

  private func setUpChannel(kind: ChannelKind) {
    switch kind {
    case .single:
      self.setUpClientConnection()
    case .pooled:
      self.setUpChannelPool()
    }
  }

  private func startRPC(
    withTracking: Bool = true
  ) -> ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse> {
    if withTracking {
      self.tracker.assert(.active)
      self.tracker.willStartRPC()
    }

    let collect = self.echo.collect(callOptions: self.callOptionsWithLogger)

    if withTracking {
      collect.status.whenSuccess { status in
        self.tracker.didFinishRPC()
        XCTAssert(status.isOk)
      }
    }

    return collect
  }

  private func assertConnectionEstablished() {
    self.tracker.assert(.active)
    let rpc = self.startRPC()
    XCTAssertNoThrow(try rpc.sendEnd().wait())
    XCTAssert(try rpc.status.wait().isOk)
    self.tracker.assert(.active)
  }

  private func gracefulShutdown(
    deadline: NIODeadline = .distantFuture,
    withTracking: Bool = true
  ) -> EventLoopFuture<Void> {
    if withTracking {
      self.tracker.willRequestGracefulShutdown()
    }

    let promise = self.group.next().makePromise(of: Void.self)
    self.channel.closeGracefully(deadline: deadline, promise: promise)

    if withTracking {
      promise.futureResult.whenComplete { _ in
        self.tracker.didShutdown()
      }
    }
    return promise.futureResult
  }
}

// MARK: - Test Helpers

extension ClientQuiescingTests {
  private func _testQuiescingWhenIdle(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    XCTAssertNoThrow(try self.gracefulShutdown().wait())
  }

  private func _testQuiescingWithNoOutstandingRPCs(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()
    XCTAssertNoThrow(try self.gracefulShutdown().wait())
  }

  private func _testQuiescingWithOneOutstandingRPC(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    let collect = self.startRPC()
    XCTAssertNoThrow(try collect.sendMessage(.empty).wait())

    let shutdownFuture = self.gracefulShutdown()
    XCTAssertNoThrow(try collect.sendEnd().wait())
    XCTAssertNoThrow(try shutdownFuture.wait())
  }

  private func _testQuiescingWithManyOutstandingRPCs(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    // Start a bunch of RPCs. Send a message on each to ensure it's open.
    let rpcs: [ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>] = (0 ..< 50).map { _ in
      self.startRPC()
    }

    for rpc in rpcs {
      XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
    }

    // Start shutting down.
    let shutdownFuture = self.gracefulShutdown()

    // All existing RPCs should continue to work. Send a message and end each.
    for rpc in rpcs {
      XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
      XCTAssertNoThrow(try rpc.sendEnd().wait())
    }

    // All RPCs should have finished so the shutdown future should complete.
    XCTAssertNoThrow(try shutdownFuture.wait())
  }

  private func _testQuiescingTimesOutAndFailsExistingRPC(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    // Tracking asserts that the RPC completes successfully: we don't expect that.
    let rpc = self.startRPC(withTracking: false)
    XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())

    let shutdownFuture = self.gracefulShutdown(deadline: .now() + .milliseconds(50))
    XCTAssertNoThrow(try shutdownFuture.wait())

    // RPC should fail because the shutdown deadline passed.
    XCTAssertThrowsError(try rpc.response.wait())
  }

  private func _testStartRPCAfterQuiescing(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    // Start an RPC, ensure it's up and running.
    let rpc = self.startRPC()
    XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
    XCTAssertNoThrow(try rpc.initialMetadata.wait())

    // Start the shutdown.
    let shutdownFuture = self.gracefulShutdown()

    // Start another RPC. This should fail immediately.
    self.tracker.assert(.shutdownRequested)
    let untrackedRPC = self.startRPC(withTracking: false)
    XCTAssertThrowsError(try untrackedRPC.response.wait())
    XCTAssertFalse(try untrackedRPC.status.wait().isOk)

    // The existing RPC should be fine.
    XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
    // .. we shutdown should complete after sending end
    XCTAssertNoThrow(try rpc.sendEnd().wait())
    XCTAssertNoThrow(try shutdownFuture.wait())
  }

  private func _testStartRPCAfterShutdownCompletes(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()
    XCTAssertNoThrow(try self.gracefulShutdown().wait())
    self.tracker.assert(.shutdown)

    // New RPCs should fail.
    let untrackedRPC = self.startRPC(withTracking: false)
    XCTAssertThrowsError(try untrackedRPC.response.wait())
    XCTAssertFalse(try untrackedRPC.status.wait().isOk)
  }

  private func _testInitiateShutdownTwice(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    let shutdown1 = self.gracefulShutdown()
    // Tracking checks 'normal' paths, this path is allowed but not normal so don't track it.
    let shutdown2 = self.gracefulShutdown(withTracking: false)

    XCTAssertNoThrow(try shutdown1.wait())
    XCTAssertNoThrow(try shutdown2.wait())
  }

  private func _testInitiateShutdownWithPastDeadline(channelKind kind: ChannelKind) {
    self.setUpChannel(kind: kind)
    self.assertConnectionEstablished()

    // Start a bunch of RPCs. Send a message on each to ensure it's open.
    let rpcs: [ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>] = (0 ..< 5).map { _ in
      self.startRPC(withTracking: false)
    }

    for rpc in rpcs {
      XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
    }

    XCTAssertNoThrow(try self.gracefulShutdown(deadline: .distantPast).wait())

    for rpc in rpcs {
      XCTAssertThrowsError(try rpc.response.wait())
    }
  }
}

// MARK: - Common Tests

extension ClientQuiescingTests {
  internal func testQuiescingWhenIdle_clientConnection() {
    self._testQuiescingWhenIdle(channelKind: .single)
  }

  internal func testQuiescingWithNoOutstandingRPCs_clientConnection() {
    self._testQuiescingWithNoOutstandingRPCs(channelKind: .single)
  }

  internal func testQuiescingWithOneOutstandingRPC_clientConnection() {
    self._testQuiescingWithOneOutstandingRPC(channelKind: .single)
  }

  internal func testQuiescingWithManyOutstandingRPCs_clientConnection() {
    self._testQuiescingWithManyOutstandingRPCs(channelKind: .single)
  }

  internal func testQuiescingTimesOutAndFailsExistingRPC_clientConnection() {
    self._testQuiescingTimesOutAndFailsExistingRPC(channelKind: .single)
  }

  internal func testStartRPCAfterQuiescing_clientConnection() {
    self._testStartRPCAfterQuiescing(channelKind: .single)
  }

  internal func testStartRPCAfterShutdownCompletes_clientConnection() {
    self._testStartRPCAfterShutdownCompletes(channelKind: .single)
  }

  internal func testInitiateShutdownTwice_clientConnection() {
    self._testInitiateShutdownTwice(channelKind: .single)
  }

  internal func testInitiateShutdownWithPastDeadline_clientConnection() {
    self._testInitiateShutdownWithPastDeadline(channelKind: .single)
  }

  internal func testQuiescingWhenIdle_channelPool() {
    self._testQuiescingWhenIdle(channelKind: .pooled)
  }

  internal func testQuiescingWithNoOutstandingRPCs_channelPool() {
    self._testQuiescingWithNoOutstandingRPCs(channelKind: .pooled)
  }

  internal func testQuiescingWithOneOutstandingRPC_channelPool() {
    self._testQuiescingWithOneOutstandingRPC(channelKind: .pooled)
  }

  internal func testQuiescingWithManyOutstandingRPCs_channelPool() {
    self._testQuiescingWithManyOutstandingRPCs(channelKind: .pooled)
  }

  internal func testQuiescingTimesOutAndFailsExistingRPC_channelPool() {
    self._testQuiescingTimesOutAndFailsExistingRPC(channelKind: .pooled)
  }

  internal func testStartRPCAfterQuiescing_channelPool() {
    self._testStartRPCAfterQuiescing(channelKind: .pooled)
  }

  internal func testStartRPCAfterShutdownCompletes_channelPool() {
    self._testStartRPCAfterShutdownCompletes(channelKind: .pooled)
  }

  internal func testInitiateShutdownTwice_channelPool() {
    self._testInitiateShutdownTwice(channelKind: .pooled)
  }

  internal func testInitiateShutdownWithPastDeadline_channelPool() {
    self._testInitiateShutdownWithPastDeadline(channelKind: .pooled)
  }
}

// MARK: - Pool Specific Tests

extension ClientQuiescingTests {
  internal func testQuiescingTimesOutAndFailsWaiters_channelPool() throws {
    self.setUpChannelPool(useSingleEventLoop: true)
    self.assertConnectionEstablished()

    // We should have an established connection so we can load it up with 100 (i.e. http/2 max
    // concurrent streams) RPCs. These are all going to fail so we disable tracking.
    let rpcs: [ClientStreamingCall<Echo_EchoRequest, Echo_EchoResponse>] = try (0 ..< 100)
      .map { _ in
        let rpc = self.startRPC(withTracking: false)
        XCTAssertNoThrow(try rpc.sendMessage(.empty).wait())
        return rpc
      }

    // Now we'll create a handful of RPCs which will be waiters. We expect these to fail too.
    let waitingRPCs = (0 ..< 50).map { _ in
      self.startRPC(withTracking: false)
    }

    // The RPCs won't complete before the deadline as we don't half close them.
    let closeFuture = self.gracefulShutdown(deadline: .now() + .milliseconds(50))
    XCTAssertNoThrow(try closeFuture.wait())

    // All open and waiting RPCs will fail.
    for rpc in rpcs {
      XCTAssertThrowsError(try rpc.response.wait())
    }

    for rpc in waitingRPCs {
      XCTAssertThrowsError(try rpc.response.wait())
    }
  }

  internal func testQuiescingAllowsForStreamsCreatedBeforeInitiatingShutdown() {
    self.setUpChannelPool(useSingleEventLoop: true)
    self.assertConnectionEstablished()

    // Each of these RPCs will create a stream 'Channel' before we initiate the shutdown but the
    // 'HTTP2Handler' may not know about each stream before we initiate shutdown. This test is to
    // validate that we allow all of these calls to run normally.
    let rpcsWhichShouldSucceed = (0 ..< 100).map { _ in
      self.startRPC()
    }

    // Initiate shutdown. The RPCs should be allowed to complete.
    let closeFuture = self.gracefulShutdown()

    // These should all fail because they were started after initiating shutdown.
    let rpcsWhichShouldFail = (0 ..< 100).map { _ in
      self.startRPC(withTracking: false)
    }

    for rpc in rpcsWhichShouldSucceed {
      XCTAssertNoThrow(try rpc.sendEnd().wait())
      XCTAssertNoThrow(try rpc.response.wait())
    }

    for rpc in rpcsWhichShouldFail {
      XCTAssertThrowsError(try rpc.sendEnd().wait())
      XCTAssertThrowsError(try rpc.response.wait())
    }

    XCTAssertNoThrow(try closeFuture.wait())
  }
}

extension ClientQuiescingTests {
  private final class RPCTracker {
    private enum _State {
      case active(Int)
      case shutdownRequested(Int)
      case shutdown
    }

    internal enum State {
      case active
      case shutdownRequested
      case shutdown
    }

    private var state = _State.active(0)
    private let lock = Lock()

    internal func assert(_ state: State, line: UInt = #line) {
      self.lock.withLockVoid {
        switch (self.state, state) {
        case (.active, .active),
             (.shutdownRequested, .shutdownRequested),
             (.shutdown, .shutdown):
          ()
        default:
          XCTFail("Expected \(state) but state is \(self.state)", line: line)
        }
      }
    }

    internal func willStartRPC() {
      self.lock.withLockVoid {
        switch self.state {
        case let .active(outstandingRPCs):
          self.state = .active(outstandingRPCs + 1)

        case let .shutdownRequested(outstandingRPCs):
          // We still increment despite the shutdown having been requested since the RPC will
          // fail immediately and we'll hit 'didFinishRPC'.
          self.state = .shutdownRequested(outstandingRPCs + 1)

        case .shutdown:
          XCTFail("Will start RPC when channel has been shutdown")
        }
      }
    }

    internal func didFinishRPC() {
      self.lock.withLockVoid {
        switch self.state {
        case let .active(outstandingRPCs):
          XCTAssertGreaterThan(outstandingRPCs, 0)
          self.state = .active(outstandingRPCs - 1)

        case let .shutdownRequested(outstandingRPCs):
          XCTAssertGreaterThan(outstandingRPCs, 0)
          self.state = .shutdownRequested(outstandingRPCs - 1)

        case .shutdown:
          XCTFail("Finished RPC after completing shutdown")
        }
      }
    }

    internal func willRequestGracefulShutdown() {
      self.lock.withLockVoid {
        switch self.state {
        case let .active(outstandingRPCs):
          self.state = .shutdownRequested(outstandingRPCs)

        case .shutdownRequested, .shutdown:
          XCTFail("Shutdown has already been requested or completed")
        }
      }
    }

    internal func didShutdown() {
      switch self.state {
      case let .active(outstandingRPCs):
        XCTFail("Shutdown completed but not requested with \(outstandingRPCs) outstanding RPCs")

      case let .shutdownRequested(outstandingRPCs):
        if outstandingRPCs != 0 {
          XCTFail("Shutdown completed with \(outstandingRPCs) outstanding RPCs")
        } else {
          // Expected case.
          self.state = .shutdown
        }

      case .shutdown:
        XCTFail("Already shutdown")
      }
    }
  }
}
