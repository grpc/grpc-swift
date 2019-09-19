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
import Foundation
@testable import GRPC
import EchoModel
import Logging
import NIOHTTP1
import NIO
import SwiftProtobuf
import XCTest

class GRPCClientStateMachineTests: GRPCTestCase {
  typealias Request = Echo_EchoRequest
  typealias Response = Echo_EchoResponse
  typealias StateMachine = GRPCClientStateMachine<Request, Response>

  var allocator = ByteBufferAllocator()

  func makeStateMachine(_ state: StateMachine.State) -> StateMachine {
    return StateMachine(
      state: state,
      logger: Logger(label: "io.grpc.testing")
    )
  }

  /// Writes a message into a new `ByteBuffer` (with length-prefixing).
  func writeMessage<T: Message>(_ message: T) throws -> ByteBuffer {
    var buffer = self.allocator.buffer(capacity: 0)
    try self.writeMessage(message, into: &buffer)
    return buffer
  }

  /// Writes the given messages into a new `ByteBuffer` (with length-prefixing).
  func writeMessages<T: Message>(_ messages: T...) throws -> ByteBuffer {
    var buffer = self.allocator.buffer(capacity: 0)
    try messages.forEach {
      try self.writeMessage($0, into: &buffer)
    }
    return buffer
  }

  /// Writes a message into the given `buffer`.
  func writeMessage<T: Message>(_ message: T, into buffer: inout ByteBuffer) throws {
    let messageData = try message.serializedData()
    let writer = LengthPrefixedMessageWriter(compression: .none)
    writer.write(messageData, into: &buffer)
  }

  /// Returns a minimally valid `HTTPResponseHead`.
  func makeResponseHead() -> HTTPResponseHead {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    return .init(version: .init(major: 2, minor: 0), status: .ok, headers: headers)
  }
}

// MARK: - Send Request Headers

extension GRPCClientStateMachineTests {
  func doTestSendRequestHeadersFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendRequestHeaders(
      host: "host",
      path: "/echo/Get",
      options: .init(),
      requestID: "bar"
    ).assertFailure {
      XCTAssertEqual($0, .invalidState)
    }
  }

  func testSendRequestHeadersFromIdle() {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .one(), server: .one))
    stateMachine.sendRequestHeaders(
      host: "host",
      path: "/echo/Get",
      options: .init(),
      requestID: "bar"
    ).assertSuccess()
  }

  func testSendRequestHeadersFromClientStreamingServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientStreamingServerIdle(client: .one(), server: .one))
  }

  func testSendRequestHeadersFromClientClosedServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerIdle(server: .one))
  }

  func testSendRequestHeadersFromStreaming() {
    self.doTestSendRequestHeadersFromInvalidState(.clientStreamingServerStreaming(client: .one(), server: .one()))
  }

  func testSendRequestHeadersFromClientClosedServerStreaming() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerStreaming(server: .one()))
  }

  func testSendRequestHeadersFromClosed() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerClosed)
  }
}

// MARK: - Send Request

extension GRPCClientStateMachineTests {
  func doTestSendRequestFromInvalidState(_ state: StateMachine.State, expected: MessageWriteError) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendRequest(.init(text: "Hello!"), allocator: self.allocator).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestSendRequestFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)

    let request: Request = .with { $0.text = "Hello!" }
    stateMachine.sendRequest(request, allocator: self.allocator).assertSuccess() { buffer in
      var buffer = buffer
      // Remove the length and compression flag prefix.
      buffer.moveReaderIndex(forwardBy: 5)
      let data = buffer.readData(length: buffer.readableBytes)!
      XCTAssertEqual(request, try Request(serializedData: data))
    }
  }

  func testSendRequestFromIdle() {
    self.doTestSendRequestFromInvalidState(.clientIdleServerIdle(client: .one(), server: .one), expected: .invalidState)
  }

  func testSendRequestFromClientStreamingServerIdle() {
    self.doTestSendRequestFromValidState(.clientStreamingServerIdle(client: .one(), server: .one))
  }

  func testSendRequestFromClientClosedServerIdle() {
    self.doTestSendRequestFromInvalidState(.clientClosedServerIdle(server: .one), expected: .cardinalityViolation)
  }

  func testSendRequestFromStreaming() {
    self.doTestSendRequestFromValidState(.clientStreamingServerStreaming(client: .one(), server: .one()))
  }

  func testSendRequestFromClientClosedServerStreaming() {
    self.doTestSendRequestFromInvalidState(.clientClosedServerIdle(server: .one), expected: .cardinalityViolation)
  }

  func testSendRequestFromClosed() {
    self.doTestSendRequestFromInvalidState(.clientClosedServerClosed, expected: .cardinalityViolation)
  }
}

// MARK: - Send End of Request Stream

extension GRPCClientStateMachineTests {
  func doTestSendEndOfRequestStreamFromInvalidState(
    _ state: StateMachine.State,
    expected: SendEndOfRequestStreamError
  ) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendEndOfRequestStream().assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestSendEndOfRequestStreamFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendEndOfRequestStream().assertSuccess()
  }

  func testSendEndOfRequestStreamFromIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientIdleServerIdle(client: .one(), server: .one),
      expected: .invalidState
    )
  }

  func testSendEndOfRequestStreamFromClientStreamingServerIdle() {
    self.doTestSendEndOfRequestStreamFromValidState(
      .clientStreamingServerIdle(client: .one(), server: .one)
    )
  }

  func testSendEndOfRequestStreamFromClientClosedServerIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerIdle(server: .one),
      expected: .alreadyClosed
    )
  }

  func testSendEndOfRequestStreamFromStreaming() {
    self.doTestSendEndOfRequestStreamFromValidState(
      .clientStreamingServerStreaming(client: .one(), server: .one())
    )
  }

  func testSendEndOfRequestStreamFromClientClosedServerStreaming() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerStreaming(server: .one()),
      expected: .alreadyClosed
    )
  }

  func testSendEndOfRequestStreamFromClosed() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerClosed,
      expected: .alreadyClosed
    )
  }
}

// MARK: - Receive Response Headers

extension GRPCClientStateMachineTests {
  func doTestReceiveResponseHeadersFromInvalidState(
    _ state: StateMachine.State,
    expected: ReceiveResponseHeadError
  ) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestReceiveResponseHeadersFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertSuccess()
  }

  func testReceiveResponseHeadersFromIdle() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientIdleServerIdle(client: .one(), server: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseHeadersFromClientStreamingServerIdle() {
    self.doTestReceiveResponseHeadersFromValidState(
      .clientStreamingServerIdle(client: .one(), server: .one)
    )
  }

  func testReceiveResponseHeadersFromClientClosedServerIdle() {
    self.doTestReceiveResponseHeadersFromValidState(
      .clientClosedServerIdle(server: .one)
    )
  }

  func testReceiveResponseHeadersFromStreaming() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientStreamingServerStreaming(client: .one(), server: .one()),
      expected: .invalidState
    )
  }

  func testReceiveResponseHeadersFromClientClosedServerStreaming() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientClosedServerStreaming(server: .one()),
      expected: .invalidState
    )
  }

  func testReceiveResponseHeadersFromClosed() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientClosedServerClosed,
      expected: .invalidState
    )
  }
}

// MARK: - Receive Response

extension GRPCClientStateMachineTests {
  func doTestReceiveResponseFromInvalidState(
    _ state: StateMachine.State,
    expected: MessageReadError
  ) throws {
    var stateMachine = self.makeStateMachine(state)

    let message = Response.with { $0.text = "Hello!" }
    var buffer = try self.writeMessage(message)

    stateMachine.receiveResponseBuffer(&buffer).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestReceiveResponseFromValidState(_ state: StateMachine.State) throws {
    var stateMachine = self.makeStateMachine(state)

    let message = Response.with { $0.text = "Hello!" }
    var buffer = try self.writeMessage(message)

    stateMachine.receiveResponseBuffer(&buffer).assertSuccess { messages in
      XCTAssertEqual(messages, [message])
    }
  }

  func testReceiveResponseFromIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientIdleServerIdle(client: .one(), server: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromClientStreamingServerIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientStreamingServerIdle(client: .one(), server: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromClientClosedServerIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientClosedServerIdle(server: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromStreaming() throws {
    try self.doTestReceiveResponseFromValidState(
      .clientStreamingServerStreaming(client: .one(), server: .one())
    )
  }

  func testReceiveResponseFromClientClosedServerStreaming() throws {
    try self.doTestReceiveResponseFromValidState(.clientClosedServerStreaming(server: .one()))
  }

  func testReceiveResponseFromClosed() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientClosedServerClosed,
      expected: .invalidState
    )
  }
}

// MARK: - Receive End of Response Stream

extension GRPCClientStateMachineTests {
  func doTestReceiveEndOfResponseStreamFromInvalidState(
    _ state: StateMachine.State,
    expected: ReceiveEndOfResponseStreamError
  ) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.receiveEndOfResponseStream(HTTPHeaders()).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestReceiveEndOfResponseStreamFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)

    var trailers = HTTPHeaders()
    trailers.add(name: GRPCHeaderName.statusCode, value: "\(GRPCStatus.Code.ok.rawValue)")
    trailers.add(name: GRPCHeaderName.statusMessage, value: "ok")

    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .ok)
      XCTAssertEqual(status.message, "ok")
    }
  }

  func testReceiveEndOfResponseStreamFromIdle() {
    self.doTestReceiveEndOfResponseStreamFromInvalidState(
      .clientIdleServerIdle(client: .one(), server: .one),
      expected: .invalidState
    )
  }

  func testReceiveEndOfResponseStreamFromClientStreamingServerIdle() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientStreamingServerIdle(client: .one(), server: .one)
    )
  }

  func testReceiveEndOfResponseStreamFromClientClosedServerIdle() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientClosedServerIdle(server: .one)
    )
  }

  func testReceiveEndOfResponseStreamFromStreaming() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientStreamingServerStreaming(client: .one(), server: .one())
    )
  }

  func testReceiveEndOfResponseStreamFromClientClosedServerStreaming() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientClosedServerStreaming(server: .one())
    )
  }

  func testReceiveEndOfResponseStreamFromClosed() {
    self.doTestReceiveEndOfResponseStreamFromInvalidState(
      .clientClosedServerClosed,
      expected: .invalidState
    )
  }
}

// MARK: - Basic RPC flow.

extension GRPCClientStateMachineTests {
  func makeTrailers(status: GRPCStatus.Code, message: String? = nil) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.add(name: GRPCHeaderName.statusCode, value: "\(status.rawValue)")
    if let message = message {
      headers.add(name: GRPCHeaderName.statusMessage, value: message)
    }
    return headers
  }

  func testSimpleUnaryFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .one(), server: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(.with { $0.text = "Hello!" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var buffer = try self.writeMessage(Response.with { $0.text = "Hello!" })
    stateMachine.receiveResponseBuffer(&buffer).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleClientStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .many(), server: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertSuccess()

    // Send some requests.
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "3" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var buffer = try self.writeMessage(Response.with { $0.text = "Hello!" })
    stateMachine.receiveResponseBuffer(&buffer).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleServerStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .one(), server: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var firstBuffer = try self.writeMessage(Response.with { $0.text = "1" })
    stateMachine.receiveResponseBuffer(&firstBuffer).assertSuccess()

    // Receive two responses in one buffer.
    var secondBuffer = try self.writeMessage(Response.with { $0.text = "2" })
    try self.writeMessage(Response.with { $0.text = "3" }, into: &secondBuffer)
    stateMachine.receiveResponseBuffer(&secondBuffer).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleBidirectionalStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .many(), server: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHead(self.makeResponseHead()).assertSuccess()

    // Interleave requests and responses:
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()

    // Receive a response.
    var firstBuffer = try self.writeMessage(Response.with { $0.text = "1" })
    stateMachine.receiveResponseBuffer(&firstBuffer).assertSuccess()

    // Send two more requests.
    stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "3" }, allocator: self.allocator).assertSuccess()

    // Receive two responses in one buffer.
    var secondBuffer = try self.writeMessage(Response.with { $0.text = "2" })
    try self.writeMessage(Response.with { $0.text = "3" }, into: &secondBuffer)
    stateMachine.receiveResponseBuffer(&secondBuffer).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }
}

// MARK: - Too many requests / responses.

extension GRPCClientStateMachineTests {
  func testSendTooManyRequestsFromClientStreamingServerIdle() {
    for messageCount in [MessageCount.one, MessageCount.many] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: messageCount))

      // One is fine.
      stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()
      // Two is not.
      stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testSendTooManyRequestsFromStreaming() {
    for readState in [ReadState.one(), ReadState.many()] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(client: .one(), server: readState))

      // One is fine.
      stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()
      // Two is not.
      stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testSendTooManyRequestsFromClosed() {
    var stateMachine = self.makeStateMachine(.clientClosedServerClosed)

    // No requests allowed!
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
  }

  func testReceiveTooManyRequests() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(client: writeState, server: .one()))

      let response = Response.with { $0.text = "foo" }

      // One response is fine.
      var firstBuffer = try self.writeMessage(response)
      stateMachine.receiveResponseBuffer(&firstBuffer).assertSuccess()

      var secondBuffer = try self.writeMessage(response)
      stateMachine.receiveResponseBuffer(&secondBuffer).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testReceiveTooManyRequestsInOneBuffer() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(client: writeState, server: .one()))

      // Write two responses into a single buffer.
      let response = Response.with { $0.text = "foo" }
      var buffer = try self.writeMessages(response, response)

      stateMachine.receiveResponseBuffer(&buffer).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }
}

// MARK: - Send Request Headers
extension GRPCClientStateMachineTests {
  func testSendRequestHeaders() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(client: .one(), server: .one))
    stateMachine.sendRequestHeaders(
      host: "localhost",
      path: "/echo/Get",
      options: CallOptions(timeout: .hours(rounding: 1), requestIDHeader: "x-grpc-id"),
      requestID: "request-id"
    ).assertSuccess { requestHead in
      XCTAssertEqual(requestHead.method, .POST)
      XCTAssertEqual(requestHead.uri, "/echo/Get")
      XCTAssertEqual(requestHead.headers["content-type"], ["application/grpc"])
      XCTAssertEqual(requestHead.headers["host"], ["localhost"])
      XCTAssertEqual(requestHead.headers["te"], ["trailers"])
      XCTAssertEqual(requestHead.headers["grpc-timeout"], ["1H"])
      XCTAssertEqual(requestHead.headers["x-grpc-id"], ["request-id"])
      XCTAssertTrue(requestHead.headers["user-agent"].first?.starts(with: "grpc-swift") ?? false)
    }
  }

  func testReceiveResponseHeadersWithOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.receiveResponseHead(responseHead).assertSuccess()
  }

  func testReceiveResponseHeadersWithNotOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .imATeapot,
      headers: HTTPHeaders()
    )

    stateMachine.receiveResponseHead(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidHTTPStatus(.imATeapot))
    }
  }

  func testReceiveResponseHeadersWithoutContentType() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok
    )

    stateMachine.receiveResponseHead(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidContentType)
    }
  }

  func testReceiveResponseHeadersWithInvalidContentType() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "video/mpeg")
    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.receiveResponseHead(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidContentType)
    }
  }

  func testReceiveResponseHeadersWithSupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    // Identity should always be supported.
    headers.add(name: "grpc-encoding", value: "identity")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.receiveResponseHead(responseHead).assertSuccess()

    switch stateMachine.state {
    case let .clientStreamingServerStreaming(_, readState):
      XCTAssertEqual(readState.reader.compressionMechanism, .identity)
    default:
      XCTFail("unexpected state \(stateMachine.state)")
    }
  }

  func testReceiveResponseHeadersWithUnsupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    headers.add(name: "grpc-encoding", value: "snappy")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.receiveResponseHead(responseHead).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding)
    }
  }

  func testReceiveResponseHeadersWithUnknownCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(client: .one(), server: .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    headers.add(name: "grpc-encoding", value: "not-a-known-compression-(probably)")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.receiveResponseHead(responseHead).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding)
    }
  }

  func testReceiveEndOfResponseStreamWithStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(server: .one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "0")
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 0))
      XCTAssertEqual(status.message, nil)
    }
  }

  func testReceiveEndOfResponseStreamWithUnknownStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(server: .one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "999")
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testReceiveEndOfResponseStreamWithNonIntStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(server: .one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "not-a-real-status-code")
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testReceiveEndOfResponseStreamWithStatusAndMessage() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(server: .one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "5")
    trailers.add(name: "grpc-message", value: "foo bar 🚀")
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 5))
      XCTAssertEqual(status.message, "foo bar 🚀")
    }
  }
}

class ReadStateTests: GRPCTestCase {
  var allocator = ByteBufferAllocator()

  func testReadWhenNoExpectedMessages() {
    var state: ReadState = .none()
    var buffer = self.allocator.buffer(capacity: 0)
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
  }

  func testReadWhenBufferContainsLengthPrefixedJunk() {
    var state: ReadState = .many()
    var buffer = self.allocator.buffer(capacity: 9)
    let bytes: [UInt8] = [
      0x00,                     // compression flag
      0x00, 0x00, 0x00, 0x04,  // message length
      0xaa, 0xbb, 0xcc, 0xdd   // message
    ]
    buffer.writeBytes(bytes)
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertFailure {
      XCTAssertEqual($0, .deserializationFailed)
    }
  }

  func testReadWithLeftOverBytesForOneExpectedMessage() throws {
    // Write a message into the buffer:
    let message = Echo_EchoRequest.with { $0.text = "Hello!" }
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = self.allocator.buffer(capacity: 0)
    writer.write(try message.serializedData(), into: &buffer)
    // And some extra junk bytes:
    let bytes: [UInt8] = [0x00]
    buffer.writeBytes(bytes)

    var state: ReadState = .one()
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertFailure {
      XCTAssertEqual($0, .leftOverBytes)
    }
  }

  func testReadTooManyMessagesForOneExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = Echo_EchoRequest.with { $0.text = "Hello!" }
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = self.allocator.buffer(capacity: 0)
    writer.write(try message.serializedData(), into: &buffer)
    writer.write(try message.serializedData(), into: &buffer)

    var state: ReadState = .one()
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
  }

  func testReadOneMessageForOneExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = Echo_EchoRequest.with { $0.text = "Hello!" }
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = self.allocator.buffer(capacity: 0)
    writer.write(try message.serializedData(), into: &buffer)

    var state: ReadState = .one()
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertSuccess {
      XCTAssertEqual($0, [message])
    }

    // We shouldn't be able to read anymore.
    XCTAssertFalse(state.canRead)
    XCTAssertEqual(state.expectedCount, .none)
  }

  func testReadOneMessageForManyExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = Echo_EchoRequest.with { $0.text = "Hello!" }
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = self.allocator.buffer(capacity: 0)
    writer.write(try message.serializedData(), into: &buffer)

    var state: ReadState = .many()
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertSuccess {
      XCTAssertEqual($0, [message])
    }

    // We should still be able to read.
    XCTAssertTrue(state.canRead)
    XCTAssertEqual(state.expectedCount, .many)
  }

  func testReadManyMessagesForManyExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = Echo_EchoRequest.with { $0.text = "Hello!" }
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = self.allocator.buffer(capacity: 0)
    writer.write(try message.serializedData(), into: &buffer)
    writer.write(try message.serializedData(), into: &buffer)
    writer.write(try message.serializedData(), into: &buffer)

    var state: ReadState = .many()
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertSuccess {
      XCTAssertEqual($0, [message, message, message])
    }

    // We should still be able to read.
    XCTAssertTrue(state.canRead)
    XCTAssertEqual(state.expectedCount, .many)
  }
}

// MARK: Result helpers

extension Result {
  /// Asserts the `Result` was a success.
  func assertSuccess(verify: (Success) throws -> Void = { _ in }) {
    switch self {
    case .success(let success):
      do {
        try verify(success)
      } catch {
        XCTFail("verify threw: \(error)")
      }
    case .failure(let error):
      XCTFail("unexpected .failure: \(error)")
    }
  }

  /// Asserts the `Result` was a failure.
  func assertFailure(verify: (Failure) throws -> Void = { _ in }) {
    switch self {
    case .success(let success):
      XCTFail("unexpected .success: \(success)")
    case .failure(let error):
      do {
        try verify(error)
      } catch {
        XCTFail("verify threw: \(error)")
      }
    }
  }
}

// MARK: ReadState, PendingWriteState, and WriteState helpers

extension ReadState {
  fileprivate init(expectedCount: MessageCount) {
    let reader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: .none,
      logger: Logger(label: "io.grpc.reader")
    )
    self.init(expectedCount: expectedCount, reader: reader)
  }

  static func none() -> ReadState {
    return .init(expectedCount: .none)
  }

  static func one() -> ReadState {
    return .init(expectedCount: .one)
  }

  static func many() -> ReadState {
    return .init(expectedCount: .many)
  }
}

extension PendingWriteState {
  static func one() -> PendingWriteState {
    return .init(expectedCount: .one, encoding: .none, contentType: .protobuf)
  }

  static func many() -> PendingWriteState {
    return .init(expectedCount: .many, encoding: .none, contentType: .protobuf)
  }
}

extension WriteState {
  static func one() -> WriteState {
    return .init(
      expectedCount: .one,
      writer: LengthPrefixedMessageWriter(compression: .none),
      contentType: .protobuf
    )
  }

  static func many() -> WriteState {
    return .init(
      expectedCount: .many,
      writer: LengthPrefixedMessageWriter(compression: .none),
      contentType: .protobuf
    )
  }
}
