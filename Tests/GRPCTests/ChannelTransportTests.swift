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
import EchoModel
import NIO
import NIOHTTP2
import XCTest

class ChannelTransportTests: GRPCTestCase {
  typealias Request = Echo_EchoRequest
  typealias RequestPart = _GRPCClientRequestPart<Request>

  typealias Response = Echo_EchoResponse
  typealias ResponsePart = _GRPCClientResponsePart<Response>

  private func makeEmbeddedTransport(
    channel: EmbeddedChannel,
    container: ResponsePartContainer<Response>,
    timeout: GRPCTimeout = .infinite
  ) -> ChannelTransport<Request, Response> {
    let transport = ChannelTransport<Request, Response>(
      eventLoop: channel.eventLoop,
      responseContainer: container,
      timeout: timeout,
      errorDelegate: nil,
      logger: self.logger
    ) { call, promise in
      channel.pipeline.addHandler(GRPCClientCallHandler(call: call)).whenComplete { result in
        switch result {
        case .success:
          promise.succeed(channel)
        case .failure(let error):
          promise.fail(error)
        }
      }
    }

    return transport
  }

  private func makeRequestHead() -> _GRPCRequestHead {
    return _GRPCRequestHead(
      method: "POST",
      scheme: "http",
      path: "/foo/bar",
      host: "localhost",
      timeout: .infinite,
      customMetadata: [:],
      encoding: .disabled
    )
  }

  private func makeRequest(_ text: String) -> _MessageContext<Request> {
    return _MessageContext(Request.with { $0.text = text }, compressed: false)
  }

  private func makeResponse(_ text: String) -> _MessageContext<Response> {
    return _MessageContext(Response.with { $0.text = text }, compressed: false)
  }

  // MARK: - Happy path

  func testUnaryHappyPath() throws {
    let channel = EmbeddedChannel()
    let responsePromise = channel.eventLoop.makePromise(of: Response.self)
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop, unaryResponsePromise: responsePromise)
    let transport = self.makeEmbeddedTransport(channel: channel, container: container)

    // Okay, let's send a unary request.
    transport.sendUnary(self.makeRequestHead(), request: .with { $0.text = "hello" }, compressed: false)

    // We haven't activated yet so the transport should buffer the message.
    XCTAssertNil(try channel.readOutbound(as: _GRPCClientRequestPart<Request>.self))

    // Activate the channel.
    channel.pipeline.fireChannelActive()

    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.requestHead)
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.message)
    XCTAssertTrue(try channel.readOutbound(as: RequestPart.self)?.isEnd ?? false)

    transport.receiveResponse(.initialMetadata([:]))
    transport.receiveResponse(.message(.init(.with { $0.text = "Hello!" }, compressed: false)))
    transport.receiveResponse(.trailingMetadata([:]))
    transport.receiveResponse(.status(.ok))

    XCTAssertNoThrow(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertNoThrow(try responsePromise.futureResult.wait())
    XCTAssertNoThrow(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    XCTAssertNoThrow(try transport.responseContainer.lazyStatusPromise.getFutureResult().wait())
  }

  func testBidirectionalHappyPath() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)

    // Okay, send the request. We'll do it before activating.
    transport.sendRequests([
      .head(self.makeRequestHead()),
      .message(self.makeRequest("1")),
      .message(self.makeRequest("2")),
      .message(self.makeRequest("3")),
      .end
    ], promise: nil)

    // We haven't activated yet so the transport should buffer the messages.
    XCTAssertNil(try channel.readOutbound(as: _GRPCClientRequestPart<Request>.self))

    // Activate the channel.
    channel.pipeline.fireChannelActive()

    // Read the parts.
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.requestHead)
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.message)
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.message)
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.message)
    XCTAssertTrue(try channel.readOutbound(as: RequestPart.self)?.isEnd ?? false)

    // Write some responses.
    XCTAssertNoThrow(try channel.writeInbound(ResponsePart.initialMetadata([:])))
    XCTAssertNoThrow(try channel.writeInbound(ResponsePart.trailingMetadata([:])))
    XCTAssertNoThrow(try channel.writeInbound(ResponsePart.status(.ok)))

    // Check the responses.
    XCTAssertNoThrow(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertNoThrow(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    XCTAssertNoThrow(try transport.responseContainer.lazyStatusPromise.getFutureResult().wait())
  }

  // MARK: - Timeout

  func testTimeoutBeforeActivating() throws {
    let timeout = try GRPCTimeout.minutes(42)
    let channel = EmbeddedChannel()
    let responsePromise = channel.eventLoop.makePromise(of: Response.self)
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop, unaryResponsePromise: responsePromise)
    let transport = self.makeEmbeddedTransport(channel: channel, container: container, timeout: timeout)

    // Advance time beyond the timeout.
    channel.embeddedEventLoop.advanceTime(by: timeout.asNIOTimeAmount)

    XCTAssertThrowsError(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertThrowsError(try responsePromise.futureResult.wait())
    XCTAssertThrowsError(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    XCTAssertEqual(try transport.responseContainer.lazyStatusPromise.getFutureResult().map { $0.code }.wait(), .deadlineExceeded)

    // Writing should fail.
    let sendPromise = channel.eventLoop.makePromise(of: Void.self)

    transport.sendRequest(.head(self.makeRequestHead()), promise: sendPromise)
    XCTAssertThrowsError(try sendPromise.futureResult.wait())
  }

  func testTimeoutAfterActivating() throws {
    let timeout = try GRPCTimeout.minutes(42)
    let channel = EmbeddedChannel()
    let responsePromise = channel.eventLoop.makePromise(of: Response.self)
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop, unaryResponsePromise: responsePromise)
    let transport = self.makeEmbeddedTransport(channel: channel, container: container, timeout: timeout)

    // Activate the channel.
    channel.pipeline.fireChannelActive()

    // Advance time beyond the timeout.
    channel.embeddedEventLoop.advanceTime(by: timeout.asNIOTimeAmount)

    XCTAssertThrowsError(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertThrowsError(try responsePromise.futureResult.wait())
    XCTAssertThrowsError(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    XCTAssertEqual(try transport.responseContainer.lazyStatusPromise.getFutureResult().map { $0.code }.wait(), .deadlineExceeded)

    // Writing should fail.
    let sendPromise = channel.eventLoop.makePromise(of: Void.self)
    transport.sendRequest(.head(self.makeRequestHead()), promise: sendPromise)
    XCTAssertThrowsError(try sendPromise.futureResult.wait())
  }

  func testTimeoutMidRPC() throws {
    let timeout = try GRPCTimeout.minutes(42)
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container, timeout: timeout)

    // Activate the channel.
    channel.pipeline.fireChannelActive()

    // Okay, send some requests.
    transport.sendRequests([
      .head(self.makeRequestHead()),
      .message(self.makeRequest("1"))
    ], promise: nil)

    // Read the parts.
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.requestHead)
    XCTAssertNotNil(try channel.readOutbound(as: RequestPart.self)?.message)

    // We'll send back the initial metadata.
    XCTAssertNoThrow(try channel.writeInbound(ResponsePart.initialMetadata([:])))
    XCTAssertNoThrow(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())

    // Advance time beyond the timeout.
    channel.embeddedEventLoop.advanceTime(by: timeout.asNIOTimeAmount)

    // Check the remaining response parts.
    XCTAssertThrowsError(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    XCTAssertEqual(try transport.responseContainer.lazyStatusPromise.getFutureResult().map { $0.code }.wait(), .deadlineExceeded)
  }

  // MARK: - Channel errors

  func testChannelBecomesInactive() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)

    // Activate and deactivate the channel.
    channel.pipeline.fireChannelActive()
    channel.pipeline.fireChannelInactive()

    // Everything should fail.
    XCTAssertThrowsError(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertThrowsError(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    // Except the status, that will never fail.
    XCTAssertNoThrow(try transport.responseContainer.lazyStatusPromise.getFutureResult().wait())
  }

  func testChannelError() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)

    // Activate the channel.
    channel.pipeline.fireChannelActive()

    // Fire an error.
    channel.pipeline.fireErrorCaught(GRPCStatus.processingError)

    // Everything should fail.
    XCTAssertThrowsError(try transport.responseContainer.lazyInitialMetadataPromise.getFutureResult().wait())
    XCTAssertThrowsError(try transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult().wait())
    // Except the status, that will never fail.
    XCTAssertNoThrow(try transport.responseContainer.lazyStatusPromise.getFutureResult().wait())
  }

  // MARK: - Test Transport after Shutdown

  func testOutboundMethodsAfterShutdown() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)
    // Close the channel.
    XCTAssertNoThrow(try channel.close().wait())

    // Sending should fail.
    let sendRequestPromise = channel.eventLoop.makePromise(of: Void.self)
    transport.sendRequest(.head(self.makeRequestHead()), promise: sendRequestPromise)
    XCTAssertThrowsError(try sendRequestPromise.futureResult.wait()) { error in
      XCTAssertEqual(error as? ChannelError, ChannelError.ioOnClosedChannel)
    }

    // Sending many should fail.
    let sendRequestsPromise = channel.eventLoop.makePromise(of: Void.self)
    transport.sendRequests([.end], promise: sendRequestsPromise)
    XCTAssertThrowsError(try sendRequestsPromise.futureResult.wait()) { error in
      XCTAssertEqual(error as? ChannelError, ChannelError.ioOnClosedChannel)
    }

    // Cancelling should fail.
    let cancelPromise = channel.eventLoop.makePromise(of: Void.self)
    transport.cancel(promise: cancelPromise)
    XCTAssertThrowsError(try cancelPromise.futureResult.wait()) { error in
      XCTAssertEqual(error as? ChannelError, ChannelError.alreadyClosed)
    }

    let channelFuture = transport.streamChannel()
    XCTAssertThrowsError(try channelFuture.wait()) { error in
      XCTAssertEqual(error as? ChannelError, ChannelError.ioOnClosedChannel)
    }
  }

  func testInboundMethodsAfterShutdown() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)
    // Close the channel.
    XCTAssertNoThrow(try channel.close().wait())

    // We'll fail the handler in the container if this one is received.
    transport.receiveResponse(.message(self.makeResponse("ignored!")))
    transport.receiveError(GRPCStatus.processingError)
  }

  func testBufferedWritesAreFailedOnClose() throws {
    let channel = EmbeddedChannel()
    let container = ResponsePartContainer<Response>(eventLoop: channel.eventLoop) { (response: Response) in
      XCTFail("No response expected but got: \(response)")
    }

    let transport = self.makeEmbeddedTransport(channel: channel, container: container)

    let requestHeadPromise = channel.eventLoop.makePromise(of: Void.self)
    transport.sendRequest(.head(self.makeRequestHead()), promise: requestHeadPromise)

    // Close the channel.
    XCTAssertNoThrow(try channel.close().wait())

    // Promise should fail.
    XCTAssertThrowsError(try requestHeadPromise.futureResult.wait())
  }
}

extension _GRPCClientRequestPart {
  var requestHead: _GRPCRequestHead? {
    switch self {
    case .head(let head):
      return head
    case .message, .end:
      return nil
    }
  }

  var message: Request? {
    switch self {
    case .message(let message):
      return message.message
    case .head, .end:
      return nil
    }
  }

  var isEnd: Bool {
    switch self {
    case .end:
      return true
    case .head, .message:
      return false
    }
  }
}
