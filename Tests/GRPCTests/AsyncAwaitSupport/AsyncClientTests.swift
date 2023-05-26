/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
import NIOCore
import NIOPosix
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
final class AsyncClientCancellationTests: GRPCTestCase {
  private var server: Server!
  private var group: EventLoopGroup!
  private var pool: GRPCChannel!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() async throws {
    if self.pool != nil {
      try await self.pool.close().get()
      self.pool = nil
    }

    if self.server != nil {
      try await self.server.close().get()
      self.server = nil
    }

    try await self.group.shutdownGracefully()
    self.group = nil

    try await super.tearDown()
  }

  private func startServer(service: CallHandlerProvider) throws {
    precondition(self.server == nil)

    self.server = try Server.insecure(group: self.group)
      .withServiceProviders([service])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  private func startServerAndClient(service: CallHandlerProvider) throws -> Echo_EchoAsyncClient {
    try self.startServer(service: service)
    return try self.makeClient(port: self.server.channel.localAddress!.port!)
  }

  private func makeClient(
    port: Int,
    configure: (inout GRPCChannelPool.Configuration) -> Void = { _ in }
  ) throws -> Echo_EchoAsyncClient {
    precondition(self.pool == nil)

    self.pool = try GRPCChannelPool.with(
      target: .host("127.0.0.1", port: port),
      transportSecurity: .plaintext,
      eventLoopGroup: self.group
    ) {
      $0.backgroundActivityLogger = self.clientLogger
      configure(&$0)
    }

    return Echo_EchoAsyncClient(channel: self.pool)
  }

  func testCancelUnaryFailsResponse() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServerAndClient(service: NeverResolvingEchoProvider())

    let get = echo.makeGetCall(.with { $0.text = "foo bar baz" })
    get.cancel()

    do {
      _ = try await get.response
      XCTFail("Expected to throw a status with code .cancelled")
    } catch let status as GRPCStatus {
      XCTAssertEqual(status.code, .cancelled)
    } catch {
      XCTFail("Expected to throw a status with code .cancelled")
    }

    // Status should be 'cancelled'.
    let status = await get.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelFailsUnaryResponseForWrappedCall() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServerAndClient(service: NeverResolvingEchoProvider())

    let task = Task {
      try await echo.get(.with { $0.text = "I'll be cancelled" })
    }

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected to throw a status with code .cancelled")
    } catch let status as GRPCStatus {
      XCTAssertEqual(status.code, .cancelled)
    } catch {
      XCTFail("Expected to throw a status with code .cancelled")
    }
  }

  func testCancelServerStreamingClosesResponseStream() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServerAndClient(service: NeverResolvingEchoProvider())

    let expand = echo.makeExpandCall(.with { $0.text = "foo bar baz" })
    expand.cancel()

    var responseStream = expand.responseStream.makeAsyncIterator()

    do {
      _ = try await responseStream.next()
      XCTFail("Expected to throw a status with code .cancelled")
    } catch let status as GRPCStatus {
      XCTAssertEqual(status.code, .cancelled)
    } catch {
      XCTFail("Expected to throw a status with code .cancelled")
    }

    // Status should be 'cancelled'.
    let status = await expand.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelServerStreamingClosesResponseStreamForWrappedCall() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServerAndClient(service: NeverResolvingEchoProvider())

    let task = Task {
      let responseStream = echo.expand(.with { $0.text = "foo bar baz" })
      var responseIterator = responseStream.makeAsyncIterator()
      do {
        _ = try await responseIterator.next()
        XCTFail("Expected to throw a status with code .cancelled")
      } catch let status as GRPCStatus {
        XCTAssertEqual(status.code, .cancelled)
      } catch {
        XCTFail("Expected to throw a status with code .cancelled")
      }
    }

    task.cancel()
    await task.value
  }

  func testCancelClientStreamingClosesRequestStreamAndFailsResponse() async throws {
    let echo = try self.startServerAndClient(service: EchoProvider())

    let collect = echo.makeCollectCall()
    // Make sure the stream is up before we cancel it.
    try await collect.requestStream.send(.with { $0.text = "foo" })
    collect.cancel()

    // Cancellation is async so loop until we error.
    while true {
      do {
        try await collect.requestStream.send(.with { $0.text = "foo" })
        try await Task.sleep(nanoseconds: 1000)
      } catch {
        break
      }
    }

    // There should be no response.
    await XCTAssertThrowsError(try await collect.response)

    // Status should be 'cancelled'.
    let status = await collect.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelClientStreamingClosesRequestStreamAndFailsResponseForWrappedCall() async throws {
    let echo = try self.startServerAndClient(service: NeverResolvingEchoProvider())
    let requests = (0 ..< 10).map { i in
      Echo_EchoRequest.with {
        $0.text = String(i)
      }
    }

    let task = Task {
      do {
        let _ = try await echo.collect(requests)
        XCTFail("Expected to throw a status with code .cancelled")
      } catch let status as GRPCStatus {
        XCTAssertEqual(status.code, .cancelled)
      } catch {
        XCTFail("Expected to throw a status with code .cancelled")
      }
    }

    task.cancel()
    await task.value
  }

  func testClientStreamingClosesRequestStreamOnEnd() async throws {
    let echo = try self.startServerAndClient(service: EchoProvider())

    let collect = echo.makeCollectCall()
    // Send and close.
    try await collect.requestStream.send(.with { $0.text = "foo" })
    collect.requestStream.finish()

    // Await the response and status.
    _ = try await collect.response
    let status = await collect.status
    XCTAssert(status.isOk)

    // Sending should fail.
    await XCTAssertThrowsError(
      try await collect.requestStream.send(.with { $0.text = "should throw" })
    )
  }

  func testCancelBidiStreamingClosesRequestStreamAndResponseStream() async throws {
    let echo = try self.startServerAndClient(service: EchoProvider())

    let update = echo.makeUpdateCall()
    // Make sure the stream is up before we cancel it.
    try await update.requestStream.send(.with { $0.text = "foo" })
    // Wait for the response.
    var responseStream = update.responseStream.makeAsyncIterator()
    _ = try await responseStream.next()

    update.cancel()

    // Cancellation is async so loop until we error.
    while true {
      do {
        try await update.requestStream.send(.with { $0.text = "foo" })
        try await Task.sleep(nanoseconds: 1000)
      } catch {
        break
      }
    }

    // Status should be 'cancelled'.
    let status = await update.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelBidiStreamingClosesRequestStreamAndResponseStreamForWrappedCall() async throws {
    let echo = try self.startServerAndClient(service: EchoProvider())
    let requests = (0 ..< 10).map { i in
      Echo_EchoRequest.with {
        $0.text = String(i)
      }
    }

    let task = Task {
      let responseStream = echo.update(requests)
      var responseIterator = responseStream.makeAsyncIterator()

      do {
        _ = try await responseIterator.next()
        XCTFail("Expected to throw a status with code .cancelled")
      } catch let status as GRPCStatus {
        XCTAssertEqual(status.code, .cancelled)
      } catch {
        XCTFail("Expected to throw a status with code .cancelled")
      }
    }

    task.cancel()
    await task.value
  }

  func testBidiStreamingClosesRequestStreamOnEnd() async throws {
    let echo = try self.startServerAndClient(service: EchoProvider())

    let update = echo.makeUpdateCall()
    // Send and close.
    try await update.requestStream.send(.with { $0.text = "foo" })
    update.requestStream.finish()

    // Await the response and status.
    let responseCount = try await update.responseStream.count()
    XCTAssertEqual(responseCount, 1)

    let status = await update.status
    XCTAssert(status.isOk)

    // Sending should fail.
    await XCTAssertThrowsError(
      try await update.requestStream.send(.with { $0.text = "should throw" })
    )
  }

  private enum RequestStreamingRPC {
    typealias Request = Echo_EchoRequest
    typealias Response = Echo_EchoResponse

    case clientStreaming(GRPCAsyncClientStreamingCall<Request, Response>)
    case bidirectionalStreaming(GRPCAsyncBidirectionalStreamingCall<Request, Response>)

    func sendRequest(_ text: String) async throws {
      switch self {
      case let .clientStreaming(call):
        try await call.requestStream.send(.with { $0.text = text })
      case let .bidirectionalStreaming(call):
        try await call.requestStream.send(.with { $0.text = text })
      }
    }

    func cancel() {
      switch self {
      case let .clientStreaming(call):
        call.cancel()
      case let .bidirectionalStreaming(call):
        call.cancel()
      }
    }
  }

  private func testSendingRequestsSuspendsWhileStreamIsNotReady(
    makeRPC: @escaping () -> RequestStreamingRPC
  ) async throws {
    // The strategy for this test is to race two different tasks. The first will attempt to send a
    // message on a request stream on a connection which will never establish. The second will sleep
    // for a little while. Each task returns a `SendOrTimedOut` event. If the message is sent then
    // the test definitely failed; it should not be possible to send a message on a stream which is
    // not open. If the time out happens first then it probably did not fail.
    enum SentOrTimedOut: Equatable, Sendable {
      case messageSent
      case timedOut
    }

    await withThrowingTaskGroup(of: SentOrTimedOut.self) { group in
      group.addTask {
        let rpc = makeRPC()

        return try await withTaskCancellationHandler {
          // This should suspend until we cancel it: we're never going to start a server so it
          // should never succeed.
          try await rpc.sendRequest("I should suspend")
          return .messageSent
        } onCancel: {
          rpc.cancel()
        }
      }

      group.addTask {
        // Wait for 100ms.
        try await Task.sleep(nanoseconds: 100_000_000)
        return .timedOut
      }

      do {
        let event = try await group.next()
        // If this isn't timed out then the message was sent before the stream was ready.
        XCTAssertEqual(event, .timedOut)
      } catch {
        XCTFail("Unexpected error \(error)")
      }

      // Cancel the other task.
      group.cancelAll()
    }
  }

  func testClientStreamingSuspendsWritesUntilStreamIsUp() async throws {
    // Make a client for a server which isn't up yet. It will continually fail to establish a
    // connection.
    let echo = try self.makeClient(port: 0)
    try await self.testSendingRequestsSuspendsWhileStreamIsNotReady {
      return .clientStreaming(echo.makeCollectCall())
    }
  }

  func testBidirectionalStreamingSuspendsWritesUntilStreamIsUp() async throws {
    // Make a client for a server which isn't up yet. It will continually fail to establish a
    // connection.
    let echo = try self.makeClient(port: 0)
    try await self.testSendingRequestsSuspendsWhileStreamIsNotReady {
      return .bidirectionalStreaming(echo.makeUpdateCall())
    }
  }

  func testConnectionFailureCancelsRequestStreamWithError() async throws {
    let echo = try self.makeClient(port: 0) {
      // Configure a short wait time; we will not start a server so fail quickly.
      $0.connectionPool.maxWaitTime = .milliseconds(10)
    }

    let update = echo.makeUpdateCall()
    await XCTAssertThrowsError(try await update.requestStream.send(.init())) { error in
      XCTAssertFalse(error is CancellationError)
    }

    let collect = echo.makeCollectCall()
    await XCTAssertThrowsError(try await collect.requestStream.send(.init())) { error in
      XCTAssertFalse(error is CancellationError)
    }
  }
}
