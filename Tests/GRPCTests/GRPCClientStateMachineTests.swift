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
    let writer = LengthPrefixedMessageWriter()
    writer.write(messageData, into: &buffer, usingCompression: .none)
  }

  /// Returns a minimally valid `HTTPResonseHead`.
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
    ).assertFailure()
  }

  func testSendRequestHeadersFromIdle() {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.one(), .one))
    stateMachine.sendRequestHeaders(
      host: "host",
      path: "/echo/Get",
      options: .init(),
      requestID: "bar"
    ).assertSuccess()
  }

  func testSendRequestHeadersFromClientStreamingServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testSendRequestHeadersFromClientClosedServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerIdle(.one))
  }

  func testSendRequestHeadersFromStreaming() {
    self.doTestSendRequestHeadersFromInvalidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testSendRequestHeadersFromClientClosedServerStreaming() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerStreaming(.one()))
  }

  func testSendRequestHeadersFromClosed() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerClosed)
  }
}

// MARK: - Send Request

extension GRPCClientStateMachineTests {
  func doTestSendRequestFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendRequest(.init(text: "Hello!"), allocator: self.allocator).assertFailure {
      XCTAssertEqual($0, .invalidState)
    }
  }

  func doTestSendRequestFromInvalidNonFatalState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendRequest(.init(text: "Hello!"), allocator: self.allocator).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
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
    self.doTestSendRequestFromInvalidState(.clientIdleServerIdle(.one(), .one))
  }

  func testSendRequestFromClientStreamingServerIdle() {
    self.doTestSendRequestFromValidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testSendRequestFromClientClosedServerIdle() {
    self.doTestSendRequestFromInvalidNonFatalState(.clientClosedServerIdle(.one))
  }

  func testSendRequestFromStreaming() {
    self.doTestSendRequestFromValidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testSendRequestFromClientClosedServerStreaming() {
    self.doTestSendRequestFromInvalidNonFatalState(.clientClosedServerIdle(.one))
  }

  func testSendRequestFromClosed() {
    self.doTestSendRequestFromInvalidNonFatalState(.clientClosedServerClosed)
  }
}

// MARK: - Send End of Request Stream

extension GRPCClientStateMachineTests {
  func doTestSendEndOfRequestStreamFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendEndOfRequestStream().assertFailure {
      XCTAssertEqual($0, .invalidState)
    }
  }

  func doTestSendEndOfRequestStreamFromInvalidNonFatalState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendEndOfRequestStream().assertFailure()
  }

  func doTestSendEndOfRequestStreamFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendEndOfRequestStream().assertSuccess()
  }

  func testSendEndOfRequestStreamFromIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidState(.clientIdleServerIdle(.one(), .one))
  }

  func testSendEndOfRequestStreamFromClientStreamingServerIdle() {
    self.doTestSendEndOfRequestStreamFromValidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testSendEndOfRequestStreamFromClientClosedServerIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidNonFatalState(.clientClosedServerIdle(.one))
  }

  func testSendEndOfRequestStreamFromStreaming() {
    self.doTestSendEndOfRequestStreamFromValidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testSendEndOfRequestStreamFromClientClosedServerStreaming() {
    self.doTestSendEndOfRequestStreamFromInvalidNonFatalState(.clientClosedServerStreaming(.one()))
  }

  func testSendEndOfRequestStreamFromClosed() {
    self.doTestSendEndOfRequestStreamFromInvalidNonFatalState(.clientClosedServerClosed)
  }
}

// MARK: - Recieve Response Headers

extension GRPCClientStateMachineTests {
  func doTestRecieveResponseHeadersFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertFailure()
  }

  func doTestRecieveResponseHeadersFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertSuccess()
  }

  func testRecieveResponseHeadersFromIdle() {
    self.doTestRecieveResponseHeadersFromInvalidState(.clientIdleServerIdle(.one(), .one))
  }

  func testRecieveResponseHeadersFromClientStreamingServerIdle() {
    self.doTestRecieveResponseHeadersFromValidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testRecieveResponseHeadersFromClientClosedServerIdle() {
    self.doTestRecieveResponseHeadersFromValidState(.clientClosedServerIdle(.one))
  }

  func testRecieveResponseHeadersFromStreaming() {
    self.doTestRecieveResponseHeadersFromInvalidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testRecieveResponseHeadersFromClientClosedServerStreaming() {
    self.doTestRecieveResponseHeadersFromInvalidState(.clientClosedServerStreaming(.one()))
  }

  func testRecieveResponseHeadersFromClosed() {
    self.doTestRecieveResponseHeadersFromInvalidState(.clientClosedServerClosed)
  }
}

// MARK: - Recieve Response

extension GRPCClientStateMachineTests {
  func doTestRecieveReponseFromInvalidState(_ state: StateMachine.State) throws {
    var stateMachine = self.makeStateMachine(state)

    let message = Response.with { $0.text = "Hello!" }
    var buffer = try self.writeMessage(message)

    stateMachine.recieveResponse(&buffer).assertFailure()
  }

  func doTestRecieveReponseFromValidState(_ state: StateMachine.State) throws {
    var stateMachine = self.makeStateMachine(state)

    let message = Response.with { $0.text = "Hello!" }
    var buffer = try self.writeMessage(message)

    stateMachine.recieveResponse(&buffer).assertSuccess { messages in
      XCTAssertEqual(messages, [message])
    }
  }

  func testRecieveReponseFromIdle() throws {
    try self.doTestRecieveReponseFromInvalidState(.clientIdleServerIdle(.one(), .one))
  }

  func testRecieveReponseFromClientStreamingServerIdle() throws {
    try self.doTestRecieveReponseFromInvalidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testRecieveReponseFromClientClosedServerIdle() throws {
    try self.doTestRecieveReponseFromInvalidState(.clientClosedServerIdle(.one))
  }

  func testRecieveReponseFromStreaming() throws {
    try self.doTestRecieveReponseFromValidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testRecieveReponseFromClientClosedServerStreaming() throws {
    try self.doTestRecieveReponseFromValidState(.clientClosedServerStreaming(.one()))
  }

  func testRecieveReponseFromClosed() throws {
    try self.doTestRecieveReponseFromInvalidState(.clientClosedServerClosed)
  }
}

// MARK: - Recieve End of Response Stream

extension GRPCClientStateMachineTests {
  func doTestRecieveEndOfResponseStreamFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.recieveEndOfResponseStream(HTTPHeaders()).assertFailure()
  }

  func doTestRecieveEndOfResponseStreamFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)

    var trailers = HTTPHeaders()
    trailers.add(name: GRPCHeaderName.statusCode, value: "\(GRPCStatus.Code.ok.rawValue)")
    trailers.add(name: GRPCHeaderName.statusMessage, value: "ok")

    stateMachine.recieveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .ok)
      XCTAssertEqual(status.message, "ok")
    }
  }

  func testRecieveEndOfResponseStreamFromIdle() {
    self.doTestRecieveEndOfResponseStreamFromInvalidState(.clientIdleServerIdle(.one(), .one))
  }

  func testRecieveEndOfResponseStreamFromClientStreamingServerIdle() {
    self.doTestRecieveEndOfResponseStreamFromValidState(.clientStreamingServerIdle(.one(), .one))
  }

  func testRecieveEndOfResponseStreamFromClientClosedServerIdle() {
    self.doTestRecieveEndOfResponseStreamFromValidState(.clientClosedServerIdle(.one))
  }

  func testRecieveEndOfResponseStreamFromStreaming() {
    self.doTestRecieveEndOfResponseStreamFromValidState(.clientStreamingServerStreaming(.one(), .one()))
  }

  func testRecieveEndOfResponseStreamFromClientClosedServerStreaming() {
    self.doTestRecieveEndOfResponseStreamFromValidState(.clientClosedServerStreaming(.one()))
  }

  func testRecieveEndOfResponseStreamFromClosed() {
    self.doTestRecieveEndOfResponseStreamFromInvalidState(.clientClosedServerClosed)
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
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.one(), .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Recieve acknowledgement.
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(.with { $0.text = "Hello!" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Recieve a response.
    var buffer = try self.writeMessage(Response.with { $0.text = "Hello!" })
    stateMachine.recieveResponse(&buffer).assertSuccess()

    // Recieve the status.
    stateMachine.recieveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleClientStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.many(), .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Recieve acknowledgement.
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertSuccess()

    // Send some requests.
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "3" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Recieve a response.
    var buffer = try self.writeMessage(Response.with { $0.text = "Hello!" })
    stateMachine.recieveResponse(&buffer).assertSuccess()

    // Recieve the status.
    stateMachine.recieveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleServerStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.one(), .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Recieve acknowledgement.
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Recieve a response.
    var firstBuffer = try self.writeMessage(Response.with { $0.text = "1" })
    stateMachine.recieveResponse(&firstBuffer).assertSuccess()

    // Recieve two responses in one buffer.
    var secondBuffer = try self.writeMessage(Response.with { $0.text = "2" })
    try self.writeMessage(Response.with { $0.text = "3" }, into: &secondBuffer)
    stateMachine.recieveResponse(&secondBuffer).assertSuccess()

    // Recieve the status.
    stateMachine.recieveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleBidirectionalStreamingFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.many(), .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(host: "foo", path: "/echo/Get", options: .init(), requestID: "bar").assertSuccess()

    // Recieve acknowledgement.
    stateMachine.recieveResponseHeaders(self.makeResponseHead()).assertSuccess()

    // Interleave requests and responses:
    stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()

    // Recieve a response.
    var firstBuffer = try self.writeMessage(Response.with { $0.text = "1" })
    stateMachine.recieveResponse(&firstBuffer).assertSuccess()

    // Send two more requests.
    stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertSuccess()
    stateMachine.sendRequest(.with { $0.text = "3" }, allocator: self.allocator).assertSuccess()

    // Recieve two responses in one buffer.
    var secondBuffer = try self.writeMessage(Response.with { $0.text = "2" })
    try self.writeMessage(Response.with { $0.text = "3" }, into: &secondBuffer)
    stateMachine.recieveResponse(&secondBuffer).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Recieve the status.
    stateMachine.recieveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }
}

// MARK: - Too many requests / responses.

extension GRPCClientStateMachineTests {
  func testSendTooManyRequestsFromClientStreamingServerIdle() {
    for responseArity in [MessageCount.one, MessageCount.many] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), responseArity))

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
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(.one(), readState))

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

  func testRecieveTooManyRequests() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(writeState, .one()))

      let response = Response.with { $0.text = "foo" }

      // One response is fine.
      var firstBuffer = try self.writeMessage(response)
      stateMachine.recieveResponse(&firstBuffer).assertSuccess()

      var secondBuffer = try self.writeMessage(response)
      stateMachine.recieveResponse(&secondBuffer).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testRecieveTooManyRequestsInOneBuffer() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self.makeStateMachine(.clientStreamingServerStreaming(writeState, .one()))

      // Write two responses into a single buffer.
      let response = Response.with { $0.text = "foo" }
      var buffer = try self.writeMessages(response, response)

      stateMachine.recieveResponse(&buffer).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }
}

// MARK: - Send Request Headers
extension GRPCClientStateMachineTests {
  func testSendRequestHeaders() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(.one(), .one))
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

  func testRecieveResponseHeadersWithOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.recieveResponseHeaders(responseHead).assertSuccess()
  }

  func testRecieveResponseHeadersWithNotOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .imATeapot,
      headers: HTTPHeaders()
    )

    stateMachine.recieveResponseHeaders(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidHTTPStatus(.imATeapot))
    }
  }

  func testRecieveResponseHeadersWithoutContentType() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok
    )

    stateMachine.recieveResponseHeaders(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidContentType)
    }
  }

  func testReciveResponseHeadersWithInvalidContentType() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "video/mpeg")
    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.recieveResponseHeaders(responseHead).assertFailure {
      XCTAssertEqual($0, .invalidContentType)
    }
  }

  func testReciveResponseHeadersWithSupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    // Identity should always be supported.
    headers.add(name: "grpc-encoding", value: "identity")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.recieveResponseHeaders(responseHead).assertSuccess()

    switch stateMachine.state {
    case let .clientStreamingServerStreaming(_, readState):
      XCTAssertEqual(readState.reader.compressionMechanism, .identity)
    default:
      XCTFail("unexpected state \(stateMachine.state)")
    }
  }

  func testReciveResponseHeadersWithUnsupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    headers.add(name: "grpc-encoding", value: "snappy")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.recieveResponseHeaders(responseHead).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding)
    }
  }

  func testReciveResponseHeadersWithUnknownCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientStreamingServerIdle(.one(), .one))

    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/grpc")
    headers.add(name: "grpc-encoding", value: "not-a-known-compression-(probably)")

    let responseHead = HTTPResponseHead(
      version: .init(major: 2, minor: 0),
      status: .ok,
      headers: headers
    )

    stateMachine.recieveResponseHeaders(responseHead).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding)
    }
  }

  func testRecieveEndOfResponseStreamWithStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(.one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "0")
    stateMachine.recieveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 0))
      XCTAssertEqual(status.message, nil)
    }
  }

  func testRecieveEndOfResponseStreamWithUnknownStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(.one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "999")
    stateMachine.recieveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testRecieveEndOfResponseStreamWithNonIntStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(.one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "not-a-real-status-code")
    stateMachine.recieveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testRecieveEndOfResponseStreamWithStatusAndMessage() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerStreaming(.one()))

    var trailers = HTTPHeaders()
    trailers.add(name: "grpc-status", value: "5")
    trailers.add(name: "grpc-message", value: "foo bar 🚀")
    stateMachine.recieveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 5))
      XCTAssertEqual(status.message, "foo bar 🚀")
    }
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
  static func one() -> ReadState {
    let reader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: .none,
      logger: Logger(label: "io.grpc.reader")
    )
    return .init(expectedCount: .one, reader: reader)
  }

  static func many() -> ReadState {
    let reader = LengthPrefixedMessageReader(
      mode: .client,
      compressionMechanism: .none,
      logger: Logger(label: "io.grpc.reader")
    )
    return .init(expectedCount: .many, reader: reader)
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
      writer: LengthPrefixedMessageWriter(),
      contentType: .protobuf
    )
  }

  static func many() -> WriteState {
    return .init(
      expectedCount: .many,
      writer: LengthPrefixedMessageWriter(),
      contentType: .protobuf
    )
  }
}
