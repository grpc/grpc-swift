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
#if compiler(>=5.6)
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

  override func setUpWithError() throws {
    try super.setUpWithError()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() async throws {
    try self.pool.close().wait()
    self.pool = nil

    try self.server.close().wait()
    self.server = nil

    try self.group.syncShutdownGracefully()
    self.group = nil

    try await super.tearDown()
  }

  private func startServer(service: CallHandlerProvider) throws -> Echo_EchoAsyncClient {
    precondition(self.server == nil)
    precondition(self.pool == nil)

    self.server = try Server.insecure(group: self.group)
      .withServiceProviders([service])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    self.pool = try GRPCChannelPool.with(
      target: .host("127.0.0.1", port: self.server.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: self.group
    ) {
      $0.backgroundActivityLogger = self.clientLogger
    }

    return Echo_EchoAsyncClient(channel: self.pool)
  }

  func testCancelUnaryFailsResponse() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServer(service: NeverResolvingEchoProvider())

    let get = echo.makeGetCall(.with { $0.text = "foo bar baz" })
    try await get.cancel()

    await XCTAssertThrowsError(try await get.response)

    // Status should be 'cancelled'.
    let status = await get.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelServerStreamingClosesResponseStream() async throws {
    // We don't want the RPC to complete before we cancel it so use the never resolving service.
    let echo = try self.startServer(service: NeverResolvingEchoProvider())

    let expand = echo.makeExpandCall(.with { $0.text = "foo bar baz" })
    try await expand.cancel()

    var responseStream = expand.responseStream.makeAsyncIterator()
    await XCTAssertThrowsError(try await responseStream.next())

    // Status should be 'cancelled'.
    let status = await expand.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testCancelClientStreamingClosesRequestStreamAndFailsResponse() async throws {
    let echo = try self.startServer(service: EchoProvider())

    let collect = echo.makeCollectCall()
    // Make sure the stream is up before we cancel it.
    try await collect.requestStream.send(.with { $0.text = "foo" })
    try await collect.cancel()

    // The next send should fail.
    await XCTAssertThrowsError(try await collect.requestStream.send(.with { $0.text = "foo" }))
    // There should be no response.
    await XCTAssertThrowsError(try await collect.response)

    // Status should be 'cancelled'.
    let status = await collect.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testClientStreamingClosesRequestStreamOnEnd() async throws {
    let echo = try self.startServer(service: EchoProvider())

    let collect = echo.makeCollectCall()
    // Send and close.
    try await collect.requestStream.send(.with { $0.text = "foo" })
    try await collect.requestStream.finish()

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
    let echo = try self.startServer(service: EchoProvider())

    let update = echo.makeUpdateCall()
    // Make sure the stream is up before we cancel it.
    try await update.requestStream.send(.with { $0.text = "foo" })
    // Wait for the response.
    var responseStream = update.responseStream.makeAsyncIterator()
    _ = try await responseStream.next()

    // Now cancel. The next send should fail and we shouldn't receive any more responses.
    try await update.cancel()
    await XCTAssertThrowsError(try await update.requestStream.send(.with { $0.text = "foo" }))
    await XCTAssertThrowsError(try await responseStream.next())

    // Status should be 'cancelled'.
    let status = await update.status
    XCTAssertEqual(status.code, .cancelled)
  }

  func testBidiStreamingClosesRequestStreamOnEnd() async throws {
    let echo = try self.startServer(service: EchoProvider())

    let update = echo.makeUpdateCall()
    // Send and close.
    try await update.requestStream.send(.with { $0.text = "foo" })
    try await update.requestStream.finish()

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
}

#endif // compiler(>=5.6)
