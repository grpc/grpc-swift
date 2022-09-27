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
#if canImport(NIOSSL)
import EchoImplementation
import EchoModel
import GRPC
import GRPCSampleData
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL
import XCTest

final class GRPCChannelPoolTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup!
  private var server: Server?
  private var channel: GRPCChannel?

  private var serverPort: Int? {
    return self.server?.channel.localAddress?.port
  }

  private var echo: Echo_EchoNIOClient {
    return Echo_EchoNIOClient(channel: self.channel!)
  }

  override func tearDown() {
    if let channel = self.channel {
      XCTAssertNoThrow(try channel.close().wait())
    }

    if let server = self.server {
      XCTAssertNoThrow(try server.close().wait())
    }

    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  private func configureEventLoopGroup(threads: Int = System.coreCount) {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
  }

  private func makeServerBuilder(withTLS: Bool) -> Server.Builder {
    let builder: Server.Builder

    if withTLS {
      builder = Server.usingTLSBackedByNIOSSL(
        on: self.group,
        certificateChain: [SampleCertificate.server.certificate],
        privateKey: SamplePrivateKey.server
      ).withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
    } else {
      builder = Server.insecure(group: self.group)
    }

    return builder
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
  }

  private func startServer(withTLS: Bool = false) {
    self.server = try! self.makeServerBuilder(withTLS: withTLS)
      .bind(host: "localhost", port: 0)
      .wait()
  }

  private func startChannel(
    withTLS: Bool = false,
    overrideTarget targetOverride: ConnectionTarget? = nil,
    _ configure: (inout GRPCChannelPool.Configuration) -> Void = { _ in }
  ) {
    let transportSecurity: GRPCChannelPool.Configuration.TransportSecurity

    if withTLS {
      let configuration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
        trustRoots: .certificates([SampleCertificate.ca.certificate])
      )
      transportSecurity = .tls(configuration)
    } else {
      transportSecurity = .plaintext
    }

    self.channel = try! GRPCChannelPool.with(
      target: targetOverride ?? .hostAndPort("localhost", self.serverPort!),
      transportSecurity: transportSecurity,
      eventLoopGroup: self.group
    ) { configuration in
      configuration.backgroundActivityLogger = self.clientLogger
      configure(&configuration)
    }
  }

  private func setUpClientAndServer(withTLS tls: Bool) {
    self.configureEventLoopGroup()
    self.startServer(withTLS: tls)
    self.startChannel(withTLS: tls) {
      // We'll allow any number of waiters since we immediately fire off a bunch of RPCs and don't
      // want to bounce off the limit as we wait for a connection to come up.
      $0.connectionPool.maxWaitersPerEventLoop = .max
    }
  }

  private func doTestUnaryRPCs(count: Int) throws {
    var futures: [EventLoopFuture<GRPCStatus>] = []
    futures.reserveCapacity(count)

    for i in 1 ... count {
      let request = Echo_EchoRequest.with { $0.text = String(describing: i) }
      let get = self.echo.get(request)
      futures.append(get.status)
    }

    let statuses = try EventLoopFuture.whenAllSucceed(futures, on: self.group.next()).wait()
    XCTAssert(statuses.allSatisfy { $0.isOk })
  }

  func testUnaryRPCs_plaintext() throws {
    self.setUpClientAndServer(withTLS: false)
    try self.doTestUnaryRPCs(count: 100)
  }

  func testUnaryRPCs_tls() throws {
    self.setUpClientAndServer(withTLS: true)
    try self.doTestUnaryRPCs(count: 100)
  }

  private func doTestClientStreamingRPCs(count: Int) throws {
    var futures: [EventLoopFuture<GRPCStatus>] = []
    futures.reserveCapacity(count)

    for i in 1 ... count {
      let request = Echo_EchoRequest.with { $0.text = String(describing: i) }
      let collect = self.echo.collect()
      collect.sendMessage(request, promise: nil)
      collect.sendMessage(request, promise: nil)
      collect.sendMessage(request, promise: nil)
      collect.sendEnd(promise: nil)
      futures.append(collect.status)
    }

    let statuses = try EventLoopFuture.whenAllSucceed(futures, on: self.group.next()).wait()
    XCTAssert(statuses.allSatisfy { $0.isOk })
  }

  func testClientStreamingRPCs_plaintext() throws {
    self.setUpClientAndServer(withTLS: false)
    try self.doTestClientStreamingRPCs(count: 100)
  }

  func testClientStreamingRPCs() throws {
    self.setUpClientAndServer(withTLS: true)
    try self.doTestClientStreamingRPCs(count: 100)
  }

  private func doTestServerStreamingRPCs(count: Int) throws {
    var futures: [EventLoopFuture<GRPCStatus>] = []
    futures.reserveCapacity(count)

    for i in 1 ... count {
      let request = Echo_EchoRequest.with { $0.text = String(describing: i) }
      let expand = self.echo.expand(request) { _ in }
      futures.append(expand.status)
    }

    let statuses = try EventLoopFuture.whenAllSucceed(futures, on: self.group.next()).wait()
    XCTAssert(statuses.allSatisfy { $0.isOk })
  }

  func testServerStreamingRPCs_plaintext() throws {
    self.setUpClientAndServer(withTLS: false)
    try self.doTestServerStreamingRPCs(count: 100)
  }

  func testServerStreamingRPCs() throws {
    self.setUpClientAndServer(withTLS: true)
    try self.doTestServerStreamingRPCs(count: 100)
  }

  private func doTestBidiStreamingRPCs(count: Int) throws {
    var futures: [EventLoopFuture<GRPCStatus>] = []
    futures.reserveCapacity(count)

    for i in 1 ... count {
      let request = Echo_EchoRequest.with { $0.text = String(describing: i) }
      let update = self.echo.update { _ in }
      update.sendMessage(request, promise: nil)
      update.sendMessage(request, promise: nil)
      update.sendMessage(request, promise: nil)
      update.sendEnd(promise: nil)
      futures.append(update.status)
    }

    let statuses = try EventLoopFuture.whenAllSucceed(futures, on: self.group.next()).wait()
    XCTAssert(statuses.allSatisfy { $0.isOk })
  }

  func testBidiStreamingRPCs_plaintext() throws {
    self.setUpClientAndServer(withTLS: false)
    try self.doTestBidiStreamingRPCs(count: 100)
  }

  func testBidiStreamingRPCs() throws {
    self.setUpClientAndServer(withTLS: true)
    try self.doTestBidiStreamingRPCs(count: 100)
  }

  func testWaitersTimeoutWhenNoConnectionCannotBeEstablished() throws {
    // 4 threads == 4 pools
    self.configureEventLoopGroup(threads: 4)
    // Don't start a server; override the target (otherwise we'll fail to unwrap `serverPort`).
    self.startChannel(overrideTarget: .unixDomainSocket("/nope")) {
      // Tiny wait time for waiters.
      $0.connectionPool.maxWaitTime = .milliseconds(50)
    }

    var statuses: [EventLoopFuture<GRPCStatus>] = []
    statuses.reserveCapacity(40)

    // Queue RPCs on each loop.
    for eventLoop in self.group.makeIterator() {
      let options = CallOptions(eventLoopPreference: .exact(eventLoop))
      for i in 0 ..< 10 {
        let get = self.echo.get(.with { $0.text = String(describing: i) }, callOptions: options)
        statuses.append(get.status)
      }
    }

    let results = try EventLoopFuture.whenAllComplete(statuses, on: self.group.next()).wait()
    for result in results {
      result.assertSuccess {
        XCTAssertEqual($0.code, .deadlineExceeded)
      }
    }
  }

  func testRPCsAreDistributedAcrossEventLoops() throws {
    self.configureEventLoopGroup(threads: 4)

    // We don't need a server here, but we do need a different target
    self.startChannel(overrideTarget: .unixDomainSocket("/nope")) {
      // Increase the max wait time: we're relying on the server will never coming up, so the RPCs
      // never complete and streams are not returned back to pools.
      $0.connectionPool.maxWaitTime = .hours(1)
    }

    var echo = self.echo
    echo.defaultCallOptions.eventLoopPreference = .indifferent

    let rpcs = (0 ..< 40).map { _ in echo.update { _ in } }

    let rpcsByEventLoop = Dictionary(grouping: rpcs, by: { ObjectIdentifier($0.eventLoop) })
    for rpcs in rpcsByEventLoop.values {
      // 40 RPCs over 4 ELs should be 10 RPCs per EL.
      XCTAssertEqual(rpcs.count, 10)
    }

    // All RPCs are waiting for connections since we never brought up a server. Each will fail when
    // we shutdown the pool.
    XCTAssertNoThrow(try self.channel?.close().wait())
    // Unset the channel to avoid shutting down again in tearDown().
    self.channel = nil

    for rpc in rpcs {
      XCTAssertEqual(try rpc.status.wait().code, .unavailable)
    }
  }

  func testWaiterLimitPerEventLoop() throws {
    self.configureEventLoopGroup(threads: 4)
    self.startChannel(overrideTarget: .unixDomainSocket("/nope")) {
      $0.connectionPool.maxWaitersPerEventLoop = 10
      $0.connectionPool.maxWaitTime = .hours(1)
    }

    let loop = self.group.next()
    let options = CallOptions(eventLoopPreference: .exact(loop))

    // The first 10 will be waiting for the connection. The 11th should be failed immediately.
    let rpcs = (1 ... 11).map { _ in
      self.echo.get(.with { $0.text = "" }, callOptions: options)
    }

    XCTAssertEqual(try rpcs.last?.status.wait().code, .resourceExhausted)

    // If we express no event loop preference then we should not get the loaded loop.
    let indifferentLoopRPCs = (1 ... 10).map {
      _ in echo.get(.with { $0.text = "" })
    }

    XCTAssert(indifferentLoopRPCs.map { $0.eventLoop }.allSatisfy { $0 !== loop })
  }

  func testWaitingRPCStartsWhenStreamCapacityIsAvailable() throws {
    self.configureEventLoopGroup(threads: 1)
    self.startServer()
    self.startChannel {
      $0.connectionPool.connectionsPerEventLoop = 1
      $0.connectionPool.maxWaitTime = .hours(1)
    }

    let lock = NIOLock()
    var order = 0

    // We need a connection to be up and running to avoid hitting the waiter limit when creating a
    // batch of RPCs in one go.
    let warmup = self.echo.get(.with { $0.text = "" })
    XCTAssert(try warmup.status.wait().isOk)

    // MAX_CONCURRENT_STREAMS should be 100, we'll create 101 RPCs, 100 of which should not have to
    // wait because there's already an active connection.
    let rpcs = (0 ..< 101).map { _ in self.echo.update { _ in }}
    // The first RPC should (obviously) complete first.
    rpcs.first!.status.whenComplete { _ in
      lock.withLock {
        XCTAssertEqual(order, 0)
        order += 1
      }
    }

    // The 101st RPC will complete once the first is completed (we explicitly terminate the 1st
    // RPC below).
    rpcs.last!.status.whenComplete { _ in
      lock.withLock {
        XCTAssertEqual(order, 1)
        order += 1
      }
    }

    // Still zero: the first RPC is still active.
    lock.withLock { XCTAssertEqual(order, 0) }
    // End the first RPC.
    XCTAssertNoThrow(try rpcs.first!.sendEnd().wait())
    XCTAssertNoThrow(try rpcs.first!.status.wait())
    lock.withLock { XCTAssertEqual(order, 1) }
    // End the last RPC.
    XCTAssertNoThrow(try rpcs.last!.sendEnd().wait())
    XCTAssertNoThrow(try rpcs.last!.status.wait())
    lock.withLock { XCTAssertEqual(order, 2) }

    // End the rest.
    for rpc in rpcs.dropFirst().dropLast() {
      XCTAssertNoThrow(try rpc.sendEnd().wait())
    }
  }

  func testRPCOnShutdownPool() {
    self.configureEventLoopGroup(threads: 1)
    self.startChannel(overrideTarget: .unixDomainSocket("/ignored"))

    let echo = self.echo

    XCTAssertNoThrow(try self.channel?.close().wait())
    // Avoid shutting down again in tearDown()
    self.channel = nil

    let get = echo.get(.with { $0.text = "" })
    XCTAssertEqual(try get.status.wait().code, .unavailable)
  }

  func testCallDeadlineIsUsedIfSoonerThanWaitingDeadline() {
    self.configureEventLoopGroup(threads: 1)
    self.startChannel(overrideTarget: .unixDomainSocket("/nope")) {
      $0.connectionPool.maxWaitTime = .hours(24)
    }

    // Deadline is sooner than the 24 hour waiter time, we expect to time out sooner rather than
    // (much) later!
    let options = CallOptions(timeLimit: .deadline(.now()))
    let timedOutOnOwnDeadline = self.echo.get(.with { $0.text = "" }, callOptions: options)

    XCTAssertEqual(try timedOutOnOwnDeadline.status.wait().code, .deadlineExceeded)
  }

  func testTLSFailuresAreClearerAtTheRPCLevel() throws {
    // Mix and match TLS.
    self.configureEventLoopGroup(threads: 1)
    self.startServer(withTLS: false)
    self.startChannel(withTLS: true) {
      $0.connectionPool.maxWaitersPerEventLoop = 10
    }

    // We can't guarantee an error happens within a certain time limit, so if we don't see what we
    // expect we'll loop until a given deadline passes.
    let testDeadline = NIODeadline.now() + .seconds(5)
    var seenError = false
    while testDeadline > .now() {
      let options = CallOptions(timeLimit: .deadline(.now() + .milliseconds(50)))
      let get = self.echo.get(.with { $0.text = "foo" }, callOptions: options)

      let status = try get.status.wait()
      XCTAssertEqual(status.code, .deadlineExceeded)

      if let cause = status.cause, cause is NIOSSLError {
        // What we expect.
        seenError = true
        break
      } else {
        // Try again.
        continue
      }
    }
    XCTAssert(seenError)

    // Now queue up a bunch of RPCs to fill up the waiter queue. We don't care about the outcome
    // of these. (They'll fail when we tear down the pool at the end of the test.)
    _ = (0 ..< 10).map { i -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> in
      let options = CallOptions(timeLimit: .deadline(.distantFuture))
      return self.echo.get(.with { $0.text = String(describing: i) }, callOptions: options)
    }

    // Queue up one more.
    let options = CallOptions(timeLimit: .deadline(.distantFuture))
    let tooManyWaiters = self.echo.get(.with { $0.text = "foo" }, callOptions: options)

    let status = try tooManyWaiters.status.wait()
    XCTAssertEqual(status.code, .resourceExhausted)

    if let cause = status.cause {
      XCTAssert(cause is NIOSSLError)
    } else {
      XCTFail("Status message did not contain a possible cause: '\(status.message ?? "nil")'")
    }
  }
}

#endif // canImport(NIOSSL)
