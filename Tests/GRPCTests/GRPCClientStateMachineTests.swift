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
import NIOHPACK
import NIO
import SwiftProtobuf
import XCTest

class GRPCClientStateMachineTests: GRPCTestCase {
  typealias Request = Echo_EchoRequest
  typealias Response = Echo_EchoResponse
  typealias StateMachine = GRPCClientStateMachine<Request, Response>

  var allocator = ByteBufferAllocator()

  func makeStateMachine(_ state: StateMachine.State) -> StateMachine {
    return StateMachine(state: state)
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

  /// Returns a minimally valid `HPACKHeaders` for a response.
  func makeResponseHeaders(
    status: String? = "200",
    contentType: String? = "application/grpc+proto"
  ) -> HPACKHeaders {
    var headers: HPACKHeaders = [:]
    status.map { headers.add(name: ":status", value: $0) }
    contentType.map { headers.add(name: "content-type", value: $0) }
    return headers
  }
}

// MARK: - Send Request Headers

extension GRPCClientStateMachineTests {
  func doTestSendRequestHeadersFromInvalidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "host",
      timeout: .infinite,
      customMetadata: [:]
    )).assertFailure {
      XCTAssertEqual($0, .invalidState)
    }
  }

  func testSendRequestHeadersFromIdle() {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "host",
      timeout: .infinite,
      customMetadata: [:]
    )).assertSuccess()
  }

  func testSendRequestHeadersFromClientActiveServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientActiveServerIdle(writeState: .one(), readArity: .one))
  }

  func testSendRequestHeadersFromClientClosedServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerIdle(readArity: .one))
  }

  func testSendRequestHeadersFromActive() {
    self.doTestSendRequestHeadersFromInvalidState(.clientActiveServerActive(writeState: .one(), readState: .one()))
  }

  func testSendRequestHeadersFromClientClosedServerActive() {
    self.doTestSendRequestHeadersFromInvalidState(.clientClosedServerActive(readState: .one()))
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
    self.doTestSendRequestFromInvalidState(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one), expected: .invalidState)
  }

  func testSendRequestFromClientActiveServerIdle() {
    self.doTestSendRequestFromValidState(.clientActiveServerIdle(writeState: .one(), readArity: .one))
  }

  func testSendRequestFromClientClosedServerIdle() {
    self.doTestSendRequestFromInvalidState(.clientClosedServerIdle(readArity: .one), expected: .cardinalityViolation)
  }

  func testSendRequestFromActive() {
    self.doTestSendRequestFromValidState(.clientActiveServerActive(writeState: .one(), readState: .one()))
  }

  func testSendRequestFromClientClosedServerActive() {
    self.doTestSendRequestFromInvalidState(.clientClosedServerIdle(readArity: .one), expected: .cardinalityViolation)
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
      .clientIdleServerIdle(pendingWriteState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testSendEndOfRequestStreamFromClientActiveServerIdle() {
    self.doTestSendEndOfRequestStreamFromValidState(
      .clientActiveServerIdle(writeState: .one(), readArity: .one)
    )
  }

  func testSendEndOfRequestStreamFromClientClosedServerIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerIdle(readArity: .one),
      expected: .alreadyClosed
    )
  }

  func testSendEndOfRequestStreamFromActive() {
    self.doTestSendEndOfRequestStreamFromValidState(
      .clientActiveServerActive(writeState: .one(), readState: .one())
    )
  }

  func testSendEndOfRequestStreamFromClientClosedServerActive() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerActive(readState: .one()),
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
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestReceiveResponseHeadersFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()
  }

  func testReceiveResponseHeadersFromIdle() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientIdleServerIdle(pendingWriteState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseHeadersFromClientActiveServerIdle() {
    self.doTestReceiveResponseHeadersFromValidState(
      .clientActiveServerIdle(writeState: .one(), readArity: .one)
    )
  }

  func testReceiveResponseHeadersFromClientClosedServerIdle() {
    self.doTestReceiveResponseHeadersFromValidState(
      .clientClosedServerIdle(readArity: .one)
    )
  }

  func testReceiveResponseHeadersFromActive() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientActiveServerActive(writeState: .one(), readState: .one()),
      expected: .invalidState
    )
  }

  func testReceiveResponseHeadersFromClientClosedServerActive() {
    self.doTestReceiveResponseHeadersFromInvalidState(
      .clientClosedServerActive(readState: .one()),
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
      .clientIdleServerIdle(pendingWriteState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromClientActiveServerIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientActiveServerIdle(writeState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromClientClosedServerIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientClosedServerIdle(readArity: .one),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromActive() throws {
    try self.doTestReceiveResponseFromValidState(
      .clientActiveServerActive(writeState: .one(), readState: .one())
    )
  }

  func testReceiveResponseFromClientClosedServerActive() throws {
    try self.doTestReceiveResponseFromValidState(.clientClosedServerActive(readState: .one()))
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
    stateMachine.receiveEndOfResponseStream(.init()).assertFailure()
  }

  func doTestReceiveEndOfResponseStreamFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)

    var trailers: HPACKHeaders = [
      GRPCHeaderName.statusCode: "0",
      GRPCHeaderName.statusMessage: "ok"
    ]

    // When the server is idle it's a "Trailers-Only" response, we need the :status and
    // content-type to make a valid set of trailers.
    switch state {
    case .clientActiveServerIdle,
         .clientClosedServerIdle:
      trailers.add(name: ":status", value: "200")
      trailers.add(name: "content-type", value: "application/grpc+proto")
    default:
      break
    }

    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .ok)
      XCTAssertEqual(status.message, "ok")
    }
  }

  func testReceiveEndOfResponseStreamFromIdle() {
    self.doTestReceiveEndOfResponseStreamFromInvalidState(
      .clientIdleServerIdle(pendingWriteState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testReceiveEndOfResponseStreamFromClientActiveServerIdle() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientActiveServerIdle(writeState: .one(), readArity: .one)
    )
  }

  func testReceiveEndOfResponseStreamFromClientClosedServerIdle() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientClosedServerIdle(readArity: .one)
    )
  }

  func testReceiveEndOfResponseStreamFromActive() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientActiveServerActive(writeState: .one(), readState: .one())
    )
  }

  func testReceiveEndOfResponseStreamFromClientClosedServerActive() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientClosedServerActive(readState: .one())
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
  func makeTrailers(status: GRPCStatus.Code, message: String? = nil) -> HPACKHeaders {
    var headers = HPACKHeaders()
    headers.add(name: GRPCHeaderName.statusCode, value: "\(status.rawValue)")
    if let message = message {
      headers.add(name: GRPCHeaderName.statusMessage, value: message)
    }
    return headers
  }

  func testSimpleUnaryFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      timeout: .infinite,
      customMetadata: [:]
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

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

  func testSimpleClientActiveFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .many(), readArity: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      timeout: .infinite,
      customMetadata: [:]
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

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

  func testSimpleServerActiveFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      timeout: .infinite,
      customMetadata: [:]
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

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

  func testSimpleBidirectionalActiveFlow() throws {
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .many(), readArity: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      timeout: .infinite,
      customMetadata: [:]
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

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
  func testSendTooManyRequestsFromClientActiveServerIdle() {
    for messageCount in [MessageArity.one, MessageArity.many] {
      var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: messageCount))

      // One is fine.
      stateMachine.sendRequest(.with { $0.text = "1" }, allocator: self.allocator).assertSuccess()
      // Two is not.
      stateMachine.sendRequest(.with { $0.text = "2" }, allocator: self.allocator).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testSendTooManyRequestsFromActive() {
    for readState in [ReadState.one(), ReadState.many()] {
      var stateMachine = self.makeStateMachine(.clientActiveServerActive(writeState: .one(), readState: readState))

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
      var stateMachine = self.makeStateMachine(.clientActiveServerActive(writeState: writeState, readState: .one()))

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
      var stateMachine = self.makeStateMachine(.clientActiveServerActive(writeState: writeState, readState: .one()))

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
    var stateMachine = self.makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      timeout: .hours(rounding: 1),
      customMetadata: ["x-grpc-id": "request-id"]
    )).assertSuccess { headers in
      XCTAssertEqual(headers[":method"], ["POST"])
      XCTAssertEqual(headers[":path"], ["/echo/Get"])
      XCTAssertEqual(headers[":authority"], ["localhost"])
      XCTAssertEqual(headers[":scheme"], ["http"])
      XCTAssertEqual(headers["content-type"], ["application/grpc"])
      XCTAssertEqual(headers["te"], ["trailers"])
      XCTAssertEqual(headers["grpc-timeout"], ["1H"])
      XCTAssertEqual(headers["x-grpc-id"], ["request-id"])
      XCTAssertTrue(headers["user-agent"].first?.starts(with: "grpc-swift") ?? false)
    }
  }

  func testReceiveResponseHeadersWithOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()
  }

  func testReceiveResponseHeadersWithNotOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    let code = "\(HTTPResponseStatus.paymentRequired.code)"
    let headers = self.makeResponseHeaders(status: code)
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidHTTPStatus(code))
    }
  }

  func testReceiveResponseHeadersWithoutContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    let headers = self.makeResponseHeaders(contentType: nil)
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidContentType(nil))
    }
  }

  func testReceiveResponseHeadersWithInvalidContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    let headers = self.makeResponseHeaders(contentType: "video/mpeg")
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidContentType("video/mpeg"))
    }
  }

  func testReceiveResponseHeadersWithSupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    var headers = self.makeResponseHeaders()
    // Identity should always be supported.
    headers.add(name: "grpc-encoding", value: "identity")

    stateMachine.receiveResponseHeaders(headers).assertSuccess()

    switch stateMachine.state {
    case let .clientActiveServerActive(_, .reading(_, reader)):
      XCTAssertEqual(reader.compressionMechanism, .identity)
    default:
      XCTFail("unexpected state \(stateMachine.state)")
    }
  }

  func testReceiveResponseHeadersWithUnsupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    var headers = self.makeResponseHeaders()
    headers.add(name: "grpc-encoding", value: "snappy")

    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding("snappy"))
    }
  }

  func testReceiveResponseHeadersWithUnknownCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(writeState: .one(), readArity: .one))

    var headers = self.makeResponseHeaders()
    headers.add(name: "grpc-encoding", value: "not-a-known-compression-(probably)")

    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding("unknown"))
    }
  }

  func testReceiveEndOfResponseStreamWithStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerActive(readState: .one()))

    let trailers: HPACKHeaders = ["grpc-status": "0"]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 0))
      XCTAssertEqual(status.message, nil)
    }
  }

  func testReceiveEndOfResponseStreamWithUnknownStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerActive(readState: .one()))

    let trailers: HPACKHeaders = ["grpc-status": "999"]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testReceiveEndOfResponseStreamWithNonIntStatus() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerActive(readState: .one()))

    let trailers: HPACKHeaders = ["grpc-status": "not-a-real-status-code"]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, .unknown)
    }
  }

  func testReceiveEndOfResponseStreamWithStatusAndMessage() throws {
    var stateMachine = self.makeStateMachine(.clientClosedServerActive(readState: .one()))

    let trailers: HPACKHeaders = [
      "grpc-status": "5",
      "grpc-message": "foo bar 🚀"
    ]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 5))
      XCTAssertEqual(status.message, "foo bar 🚀")
    }
  }
}

class ReadStateTests: GRPCTestCase {
  var allocator = ByteBufferAllocator()

  func testReadWhenNoExpectedMessages() {
    var state: ReadState = .notReading
    var buffer = self.allocator.buffer(capacity: 0)
    state.readMessages(&buffer, as: Echo_EchoRequest.self).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
    state.assertNotReading()
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
    state.assertNotReading()
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
    state.assertNotReading()
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
    state.assertNotReading()
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
    state.assertNotReading()
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
    state.assertReading()
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
    state.assertReading()
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
    let reader = LengthPrefixedMessageReader(compressionMechanism: .none)
    return .reading(.one, reader)
  }

  static func many() -> ReadState {
    let reader = LengthPrefixedMessageReader(compressionMechanism: .none)
    return .reading(.many, reader)
  }

  func assertReading() {
    switch self {
    case .reading:
      ()
    case .notReading:
      XCTFail("unexpected state .notReading")
    }
  }

  func assertNotReading() {
    switch self {
    case .reading:
      XCTFail("unexpected state .reading")
    case .notReading:
      ()
    }
  }
}

extension PendingWriteState {
  static func one() -> PendingWriteState {
    return .init(arity: .one, compression: .none, contentType: .protobuf)
  }

  static func many() -> PendingWriteState {
    return .init(arity: .many, compression: .none, contentType: .protobuf)
  }
}

extension WriteState {
  static func one() -> WriteState {
    return .writing(.one, .protobuf, LengthPrefixedMessageWriter(compression: .none))
  }

  static func many() -> WriteState {
    return .writing(.many, .protobuf, LengthPrefixedMessageWriter(compression: .none))
  }
}
