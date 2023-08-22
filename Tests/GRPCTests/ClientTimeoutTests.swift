/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import EchoModel
import Foundation
@testable import GRPC
import Logging
import NIOCore
import NIOEmbedded
import NIOHTTP2
import SwiftProtobuf
import XCTest

class ClientTimeoutTests: GRPCTestCase {
  var channel: EmbeddedChannel!
  var client: Echo_EchoNIOClient!

  let timeout = TimeAmount.milliseconds(100)
  var callOptions: CallOptions {
    // We use a deadline here because internally we convert timeouts into deadlines by diffing
    // with `DispatchTime.now()`. We therefore need the deadline to be known in advance. Note we
    // use zero because `EmbeddedEventLoop`s time starts at zero.
    var options = self.callOptionsWithLogger
    options.timeLimit = .deadline(.uptimeNanoseconds(0) + self.timeout)
    return options
  }

  // Note: this is not related to the call timeout since we're using an EmbeddedChannel. We require
  // this in case the timeout doesn't work.
  let testTimeout: TimeInterval = 0.1

  override func setUp() {
    super.setUp()

    let connection = EmbeddedGRPCChannel(logger: self.clientLogger)
    XCTAssertNoThrow(
      try connection.embeddedChannel
        .connect(to: SocketAddress(unixDomainSocketPath: "/foo"))
    )
    let client = Echo_EchoNIOClient(channel: connection, defaultCallOptions: self.callOptions)

    self.channel = connection.embeddedChannel
    self.client = client
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.finish())
    super.tearDown()
  }

  func assertRPCTimedOut(
    _ response: EventLoopFuture<Echo_EchoResponse>,
    expectation: XCTestExpectation
  ) {
    response.whenComplete { result in
      switch result {
      case let .success(response):
        XCTFail("unexpected response: \(response)")
      case let .failure(error):
        XCTAssertTrue(error is GRPCError.RPCTimedOut)
      }
      expectation.fulfill()
    }
  }

  func assertDeadlineExceeded(
    _ status: EventLoopFuture<GRPCStatus>,
    expectation: XCTestExpectation
  ) {
    status.whenComplete { result in
      switch result {
      case let .success(status):
        XCTAssertEqual(status.code, .deadlineExceeded)
      case let .failure(error):
        XCTFail("unexpected error: \(error)")
      }
      expectation.fulfill()
    }
  }

  func testUnaryTimeoutAfterSending() throws {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.get(Echo_EchoRequest(text: "foo"))
    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testServerStreamingTimeoutAfterSending() throws {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.expand(Echo_EchoRequest(text: "foo bar baz")) { _ in }
    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testClientStreamingTimeoutBeforeSending() throws {
    let responseExpectation = self.expectation(description: "response fulfilled")
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.collect()
    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertRPCTimedOut(call.response, expectation: responseExpectation)
    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [responseExpectation, statusExpectation], timeout: self.testTimeout)
  }

  func testClientStreamingTimeoutAfterSending() throws {
    let responseExpectation = self.expectation(description: "response fulfilled")
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.collect()

    self.assertRPCTimedOut(call.response, expectation: responseExpectation)
    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)
    call.sendEnd(promise: nil)
    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.wait(for: [responseExpectation, statusExpectation], timeout: 1.0)
  }

  func testBidirectionalStreamingTimeoutBeforeSending() {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.update { _ in }

    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testBidirectionalStreamingTimeoutAfterSending() {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.update { _ in }

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)
    call.sendEnd(promise: nil)
    self.channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }
}

// Unchecked as it uses an 'EmbeddedChannel'.
extension EmbeddedGRPCChannel: @unchecked Sendable {}

private final class EmbeddedGRPCChannel: GRPCChannel {
  let embeddedChannel: EmbeddedChannel
  let multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

  let logger: Logger
  let scheme: String
  let authority: String
  let errorDelegate: ClientErrorDelegate?

  func close() -> EventLoopFuture<Void> {
    return self.embeddedChannel.close()
  }

  var eventLoop: EventLoop {
    return self.embeddedChannel.eventLoop
  }

  init(
    logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() }),
    errorDelegate: ClientErrorDelegate? = nil
  ) {
    let embeddedChannel = EmbeddedChannel()
    self.embeddedChannel = embeddedChannel
    self.logger = logger
    self.multiplexer = embeddedChannel.configureGRPCClient(
      errorDelegate: errorDelegate,
      logger: logger
    ).flatMap {
      embeddedChannel.pipeline.handler(type: HTTP2StreamMultiplexer.self)
    }
    self.scheme = "http"
    self.authority = "localhost"
    self.errorDelegate = errorDelegate
  }

  internal func makeCall<Request: Message, Response: Message>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return Call(
      path: path,
      type: type,
      eventLoop: self.eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: self.makeStreamChannel(),
        authority: self.authority,
        scheme: self.scheme,
        // This is internal and only for testing, so max is fine here.
        maximumReceiveMessageLength: .max,
        errorDelegate: self.errorDelegate
      )
    )
  }

  internal func makeCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return Call(
      path: path,
      type: type,
      eventLoop: self.eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: self.makeStreamChannel(),
        authority: self.authority,
        scheme: self.scheme,
        // This is internal and only for testing, so max is fine here.
        maximumReceiveMessageLength: .max,
        errorDelegate: self.errorDelegate
      )
    )
  }

  private func makeStreamChannel() -> EventLoopFuture<Channel> {
    let promise = self.eventLoop.makePromise(of: Channel.self)
    self.multiplexer.whenSuccess {
      $0.createStreamChannel(promise: promise) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    }
    return promise.futureResult
  }
}
