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
import NIOHPACK
import NIOHTTP1
import SwiftProtobuf
import XCTest

class GRPCClientStateMachineTests: GRPCTestCase {
  typealias Request = Echo_EchoRequest
  typealias Response = Echo_EchoResponse
  typealias StateMachine = GRPCClientStateMachine

  var allocator = ByteBufferAllocator()

  func makeStateMachine(_ state: StateMachine.State) -> StateMachine {
    return StateMachine(state: state)
  }

  /// Writes a message into a new `ByteBuffer` (with length-prefixing).
  func writeMessage(_ message: String) throws -> ByteBuffer {
    let buffer = self.allocator.buffer(string: message)

    let writer = LengthPrefixedMessageWriter(compression: .none)
    return try writer.write(buffer: buffer, allocator: self.allocator, compressed: false)
  }

  /// Writes a message into the given `buffer`.
  func writeMessage(_ message: String, into buffer: inout ByteBuffer) throws {
    var other = try self.writeMessage(message)
    buffer.writeBuffer(&other)
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
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertFailure {
      XCTAssertEqual($0, .invalidState)
    }
  }

  func testSendRequestHeadersFromIdle() {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "host",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertSuccess()
  }

  func testSendRequestHeadersFromClientActiveServerIdle() {
    self.doTestSendRequestHeadersFromInvalidState(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))
  }

  func testSendRequestHeadersFromClientClosedServerIdle() {
    self
      .doTestSendRequestHeadersFromInvalidState(
        .clientClosedServerIdle(pendingReadState: .init(
          arity: .one,
          messageEncoding: .disabled
        ))
      )
  }

  func testSendRequestHeadersFromActive() {
    self
      .doTestSendRequestHeadersFromInvalidState(.clientActiveServerActive(
        writeState: .one(),
        readState: .one()
      ))
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
    stateMachine.sendRequest(
      ByteBuffer(string: "Hello!"),
      compressed: false,
      allocator: self.allocator
    ).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestSendRequestFromValidState(_ state: StateMachine.State) {
    var stateMachine = self.makeStateMachine(state)

    let request = "Hello!"
    stateMachine.sendRequest(
      ByteBuffer(string: request),
      compressed: false,
      allocator: self.allocator
    ).assertSuccess { buffer in
      var buffer = buffer
      // Remove the length and compression flag prefix.
      buffer.moveReaderIndex(forwardBy: 5)
      let data = buffer.readString(length: buffer.readableBytes)!
      XCTAssertEqual(request, data)
    }
  }

  func testSendRequestFromIdle() {
    self.doTestSendRequestFromInvalidState(
      .clientIdleServerIdle(pendingWriteState: .one(), readArity: .one),
      expected: .invalidState
    )
  }

  func testSendRequestFromClientActiveServerIdle() {
    self.doTestSendRequestFromValidState(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))
  }

  func testSendRequestFromClientClosedServerIdle() {
    self.doTestSendRequestFromInvalidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled)),
      expected: .cardinalityViolation
    )
  }

  func testSendRequestFromActive() {
    self
      .doTestSendRequestFromValidState(.clientActiveServerActive(
        writeState: .one(),
        readState: .one()
      ))
  }

  func testSendRequestFromClientClosedServerActive() {
    self.doTestSendRequestFromInvalidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled)),
      expected: .cardinalityViolation
    )
  }

  func testSendRequestFromClosed() {
    self.doTestSendRequestFromInvalidState(
      .clientClosedServerClosed,
      expected: .cardinalityViolation
    )
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
      .clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: .one, messageEncoding: .disabled)
      )
    )
  }

  func testSendEndOfRequestStreamFromClientClosedServerIdle() {
    self.doTestSendEndOfRequestStreamFromInvalidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled)),
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
      .clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: .one, messageEncoding: .disabled)
      )
    )
  }

  func testReceiveResponseHeadersFromClientClosedServerIdle() {
    self.doTestReceiveResponseHeadersFromValidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled))
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

    let message = "Hello!"
    var buffer = try self.writeMessage(message)

    stateMachine.receiveResponseBuffer(&buffer, maxMessageLength: .max).assertFailure {
      XCTAssertEqual($0, expected)
    }
  }

  func doTestReceiveResponseFromValidState(_ state: StateMachine.State) throws {
    var stateMachine = self.makeStateMachine(state)

    let message = "Hello!"
    var buffer = try self.writeMessage(message)

    stateMachine.receiveResponseBuffer(&buffer, maxMessageLength: .max).assertSuccess { messages in
      XCTAssertEqual(messages, [ByteBuffer(string: message)])
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
      .clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: .one, messageEncoding: .disabled)
      ),
      expected: .invalidState
    )
  }

  func testReceiveResponseFromClientClosedServerIdle() throws {
    try self.doTestReceiveResponseFromInvalidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled)),
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
      GRPCHeaderName.statusMessage: "ok",
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
      .clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: .one, messageEncoding: .disabled)
      )
    )
  }

  func testReceiveEndOfResponseStreamFromClientClosedServerIdle() {
    self.doTestReceiveEndOfResponseStreamFromValidState(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled))
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

  private func doTestReceiveEndStreamOnDataWhenActive(_ state: StateMachine.State) throws {
    var stateMachine = self.makeStateMachine(state)
    let status = try assertNotNil(stateMachine.receiveEndOfResponseStream())
    XCTAssertEqual(status.code, .internalError)
  }

  func testReceiveEndStreamOnDataClientActiveServerIdle() throws {
    try self.doTestReceiveEndStreamOnDataWhenActive(
      .clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: .one, messageEncoding: .disabled)
      )
    )
  }

  func testReceiveEndStreamOnDataClientClosedServerIdle() throws {
    try self.doTestReceiveEndStreamOnDataWhenActive(
      .clientClosedServerIdle(pendingReadState: .init(arity: .one, messageEncoding: .disabled))
    )
  }

  func testReceiveEndStreamOnDataClientActiveServerActive() throws {
    try self.doTestReceiveEndStreamOnDataWhenActive(
      .clientActiveServerActive(writeState: .one(), readState: .one())
    )
  }

  func testReceiveEndStreamOnDataClientClosedServerActive() throws {
    try self.doTestReceiveEndStreamOnDataWhenActive(
      .clientClosedServerActive(readState: .one())
    )
  }

  func testReceiveEndStreamOnDataWhenClosed() {
    var stateMachine = self.makeStateMachine(.clientClosedServerClosed)
    // Already closed, end stream is ignored.
    XCTAssertNil(stateMachine.receiveEndOfResponseStream())
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
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(
      ByteBuffer(string: "Hello!"),
      compressed: false,
      allocator: self.allocator
    ).assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var buffer = try self.writeMessage("Hello!")
    stateMachine.receiveResponseBuffer(&buffer, maxMessageLength: .max).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleClientActiveFlow() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .many(), readArity: .one))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

    // Send some requests.
    stateMachine.sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
      .assertSuccess()
    stateMachine.sendRequest(ByteBuffer(string: "2"), compressed: false, allocator: self.allocator)
      .assertSuccess()
    stateMachine.sendRequest(ByteBuffer(string: "3"), compressed: false, allocator: self.allocator)
      .assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var buffer = try self.writeMessage("Hello!")
    stateMachine.receiveResponseBuffer(&buffer, maxMessageLength: .max).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleServerActiveFlow() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

    // Send a request.
    stateMachine.sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
      .assertSuccess()

    // Close the request stream.
    stateMachine.sendEndOfRequestStream().assertSuccess()

    // Receive a response.
    var firstBuffer = try self.writeMessage("1")
    stateMachine.receiveResponseBuffer(&firstBuffer, maxMessageLength: .max).assertSuccess()

    // Receive two responses in one buffer.
    var secondBuffer = try self.writeMessage("2")
    try self.writeMessage("3", into: &secondBuffer)
    stateMachine.receiveResponseBuffer(&secondBuffer, maxMessageLength: .max).assertSuccess()

    // Receive the status.
    stateMachine.receiveEndOfResponseStream(self.makeTrailers(status: .ok)).assertSuccess()
  }

  func testSimpleBidirectionalActiveFlow() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .many(), readArity: .many))

    // Initiate the RPC
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "https",
      path: "/echo/Get",
      host: "foo",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )).assertSuccess()

    // Receive acknowledgement.
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()

    // Interleave requests and responses:
    stateMachine.sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
      .assertSuccess()

    // Receive a response.
    var firstBuffer = try self.writeMessage("1")
    stateMachine.receiveResponseBuffer(&firstBuffer, maxMessageLength: .max).assertSuccess()

    // Send two more requests.
    stateMachine.sendRequest(ByteBuffer(string: "2"), compressed: false, allocator: self.allocator)
      .assertSuccess()
    stateMachine.sendRequest(ByteBuffer(string: "3"), compressed: false, allocator: self.allocator)
      .assertSuccess()

    // Receive two responses in one buffer.
    var secondBuffer = try self.writeMessage("2")
    try self.writeMessage("3", into: &secondBuffer)
    stateMachine.receiveResponseBuffer(&secondBuffer, maxMessageLength: .max).assertSuccess()

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
      var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
        writeState: .one(),
        pendingReadState: .init(arity: messageCount, messageEncoding: .disabled)
      ))

      // One is fine.
      stateMachine
        .sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
        .assertSuccess()
      // Two is not.
      stateMachine
        .sendRequest(ByteBuffer(string: "2"), compressed: false, allocator: self.allocator)
        .assertFailure {
          XCTAssertEqual($0, .cardinalityViolation)
        }
    }
  }

  func testSendTooManyRequestsFromActive() {
    for readState in [ReadState.one(), ReadState.many()] {
      var stateMachine = self
        .makeStateMachine(.clientActiveServerActive(writeState: .one(), readState: readState))

      // One is fine.
      stateMachine
        .sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
        .assertSuccess()
      // Two is not.
      stateMachine
        .sendRequest(ByteBuffer(string: "2"), compressed: false, allocator: self.allocator)
        .assertFailure {
          XCTAssertEqual($0, .cardinalityViolation)
        }
    }
  }

  func testSendTooManyRequestsFromClosed() {
    var stateMachine = self.makeStateMachine(.clientClosedServerClosed)

    // No requests allowed!
    stateMachine.sendRequest(ByteBuffer(string: "1"), compressed: false, allocator: self.allocator)
      .assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
  }

  func testReceiveTooManyRequests() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self
        .makeStateMachine(.clientActiveServerActive(writeState: writeState, readState: .one()))

      // One response is fine.
      var firstBuffer = try self.writeMessage("foo")
      stateMachine.receiveResponseBuffer(&firstBuffer, maxMessageLength: .max).assertSuccess()

      var secondBuffer = try self.writeMessage("bar")
      stateMachine.receiveResponseBuffer(&secondBuffer, maxMessageLength: .max).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }

  func testReceiveTooManyRequestsInOneBuffer() throws {
    for writeState in [WriteState.one(), WriteState.many()] {
      var stateMachine = self
        .makeStateMachine(.clientActiveServerActive(writeState: writeState, readState: .one()))

      // Write two responses into a single buffer.
      var buffer = try self.writeMessage("foo")
      var other = try self.writeMessage("bar")
      buffer.writeBuffer(&other)

      stateMachine.receiveResponseBuffer(&buffer, maxMessageLength: .max).assertFailure {
        XCTAssertEqual($0, .cardinalityViolation)
      }
    }
  }
}

// MARK: - Send Request Headers

extension GRPCClientStateMachineTests {
  func testSendRequestHeaders() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .now() + .hours(1),
      customMetadata: ["x-grpc-id": "request-id"],
      encoding: .enabled(.init(
        forRequests: .identity,
        acceptableForResponses: [.identity],
        decompressionLimit: .ratio(10)
      ))
    )).assertSuccess { headers in
      XCTAssertEqual(headers[":method"], ["POST"])
      XCTAssertEqual(headers[":path"], ["/echo/Get"])
      XCTAssertEqual(headers[":authority"], ["localhost"])
      XCTAssertEqual(headers[":scheme"], ["http"])
      XCTAssertEqual(headers["content-type"], ["application/grpc"])
      XCTAssertEqual(headers["te"], ["trailers"])
      // We convert the deadline into a timeout, we can't be exactly sure what that timeout is.
      XCTAssertTrue(headers.contains(name: "grpc-timeout"))
      XCTAssertEqual(headers["x-grpc-id"], ["request-id"])
      XCTAssertEqual(headers["grpc-encoding"], ["identity"])
      XCTAssertTrue(headers["grpc-accept-encoding"].contains("identity"))
      XCTAssertTrue(headers["user-agent"].first?.starts(with: "grpc-swift") ?? false)
    }
  }

  func testSendRequestHeadersNormalizesCustomMetadata() throws {
    // `HPACKHeaders` uses case-insensitive lookup for header names so we can't check the equality
    // for individual headers. We'll pull out the entries we care about by matching a sentinel value
    // and then compare `HPACKHeaders` instances (since the equality check *is* case sensitive).
    let filterKey = "a-key-for-filtering"
    let customMetadata: HPACKHeaders = [
      "partiallyLower": filterKey,
      "ALLUPPER": filterKey,
    ]

    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: customMetadata,
      encoding: .disabled
    )).assertSuccess { headers in
      // Pull out the entries we care about by matching values
      let filtered = headers.filter { _, value, _ in
        value == filterKey
      }.map { name, value, _ in
        (name, value)
      }

      let justCustomMetadata = HPACKHeaders(filtered)
      let expected: HPACKHeaders = [
        "partiallylower": filterKey,
        "allupper": filterKey,
      ]

      XCTAssertEqual(justCustomMetadata, expected)
    }
  }

  func testSendRequestHeadersWithCustomUserAgent() throws {
    let customMetadata: HPACKHeaders = [
      "user-agent": "test-user-agent",
    ]

    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: customMetadata,
      encoding: .enabled(.init(
        forRequests: nil,
        acceptableForResponses: [],
        decompressionLimit: .ratio(10)
      ))
    )).assertSuccess { headers in
      XCTAssertEqual(headers["user-agent"], ["test-user-agent"])
    }
  }

  func testSendRequestHeadersWithNoCompressionInEitherDirection() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: ["x-grpc-id": "request-id"],
      encoding: .enabled(.init(
        forRequests: nil,
        acceptableForResponses: [],
        decompressionLimit: .ratio(10)
      ))
    )).assertSuccess { headers in
      XCTAssertFalse(headers.contains(name: "grpc-encoding"))
      XCTAssertFalse(headers.contains(name: "grpc-accept-encoding"))
    }
  }

  func testSendRequestHeadersWithNoCompressionForRequests() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: ["x-grpc-id": "request-id"],
      encoding: .enabled(.init(
        forRequests: nil,
        acceptableForResponses: [.identity, .gzip],
        decompressionLimit: .ratio(10)
      ))
    )).assertSuccess { headers in
      XCTAssertFalse(headers.contains(name: "grpc-encoding"))
      XCTAssertTrue(headers.contains(name: "grpc-accept-encoding"))
    }
  }

  func testSendRequestHeadersWithNoCompressionForResponses() throws {
    var stateMachine = self
      .makeStateMachine(.clientIdleServerIdle(pendingWriteState: .one(), readArity: .one))
    stateMachine.sendRequestHeaders(requestHead: .init(
      method: "POST",
      scheme: "http",
      path: "/echo/Get",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: ["x-grpc-id": "request-id"],
      encoding: .enabled(.init(
        forRequests: .gzip,
        acceptableForResponses: [],
        decompressionLimit: .ratio(10)
      ))
    )).assertSuccess { headers in
      XCTAssertEqual(headers["grpc-encoding"], ["gzip"])
      // This asymmetry is strange but allowed: if a client does not advertise support of the
      // compression it is using, the server may still process the message so long as it too
      // supports the compression.
      XCTAssertFalse(headers.contains(name: "grpc-accept-encoding"))
    }
  }

  func testReceiveResponseHeadersWithOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))
    stateMachine.receiveResponseHeaders(self.makeResponseHeaders()).assertSuccess()
  }

  func testReceiveResponseHeadersWithNotOkStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let code = "\(HTTPResponseStatus.paymentRequired.code)"
    let headers = self.makeResponseHeaders(status: code)
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidHTTPStatus(code))
    }
  }

  func testReceiveResponseHeadersWithoutContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let headers = self.makeResponseHeaders(contentType: nil)
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidContentType(nil))
    }
  }

  func testReceiveResponseHeadersWithInvalidContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let headers = self.makeResponseHeaders(contentType: "video/mpeg")
    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .invalidContentType("video/mpeg"))
    }
  }

  func testReceiveResponseHeadersWithSupportedCompressionMechanism() throws {
    let configuration = ClientMessageEncoding.Configuration(
      forRequests: .none,
      acceptableForResponses: [.identity],
      decompressionLimit: .ratio(1)
    )
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .enabled(configuration))
    ))

    var headers = self.makeResponseHeaders()
    // Identity should always be supported.
    headers.add(name: "grpc-encoding", value: "identity")

    stateMachine.receiveResponseHeaders(headers).assertSuccess()

    switch stateMachine.state {
    case let .clientActiveServerActive(_, .reading(_, reader)):
      XCTAssertEqual(reader.compression?.algorithm, .identity)
    default:
      XCTFail("unexpected state \(stateMachine.state)")
    }
  }

  func testReceiveResponseHeadersWithUnsupportedCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    var headers = self.makeResponseHeaders()
    headers.add(name: "grpc-encoding", value: "snappy")

    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding("snappy"))
    }
  }

  func testReceiveResponseHeadersWithUnknownCompressionMechanism() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    var headers = self.makeResponseHeaders()
    headers.add(name: "grpc-encoding", value: "not-a-known-compression-(probably)")

    stateMachine.receiveResponseHeaders(headers).assertFailure {
      XCTAssertEqual($0, .unsupportedMessageEncoding("not-a-known-compression-(probably)"))
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
      "grpc-message": "foo bar 🚀",
    ]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 5))
      XCTAssertEqual(status.message, "foo bar 🚀")
    }
  }

  func testReceiveTrailersOnlyEndOfResponseStreamWithoutContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let trailers: HPACKHeaders = [
      ":status": "200",
      "grpc-status": "5",
      "grpc-message": "foo bar 🚀",
    ]
    stateMachine.receiveEndOfResponseStream(trailers).assertSuccess { status in
      XCTAssertEqual(status.code, GRPCStatus.Code(rawValue: 5))
      XCTAssertEqual(status.message, "foo bar 🚀")
    }
  }

  func testReceiveTrailersOnlyEndOfResponseStreamWithInvalidContentType() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let trailers: HPACKHeaders = [
      ":status": "200",
      "grpc-status": "5",
      "grpc-message": "foo bar 🚀",
      "content-type": "invalid",
    ]
    stateMachine.receiveEndOfResponseStream(trailers).assertFailure { error in
      XCTAssertEqual(error, .invalidContentType("invalid"))
    }
  }

  func testReceiveTrailersOnlyEndOfResponseStreamWithInvalidHTTPStatusAndValidGRPCStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let trailers: HPACKHeaders = [
      ":status": "418",
      "grpc-status": "5",
    ]
    stateMachine.receiveEndOfResponseStream(trailers).assertFailure { error in
      XCTAssertEqual(
        error,
        .invalidHTTPStatusWithGRPCStatus(GRPCStatus(
          code: GRPCStatus.Code(rawValue: 5)!,
          message: nil
        ))
      )
    }
  }

  func testReceiveTrailersOnlyEndOfResponseStreamWithInvalidHTTPStatusAndNoGRPCStatus() throws {
    var stateMachine = self.makeStateMachine(.clientActiveServerIdle(
      writeState: .one(),
      pendingReadState: .init(arity: .one, messageEncoding: .disabled)
    ))

    let trailers: HPACKHeaders = [":status": "418"]
    stateMachine.receiveEndOfResponseStream(trailers).assertFailure { error in
      XCTAssertEqual(error, .invalidHTTPStatus("418"))
    }
  }
}

class ReadStateTests: GRPCTestCase {
  var allocator = ByteBufferAllocator()

  func testReadWhenNoExpectedMessages() {
    var state: ReadState = .notReading
    var buffer = self.allocator.buffer(capacity: 0)
    state.readMessages(&buffer, maxLength: .max).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
    state.assertNotReading()
  }

  func testReadWithLeftOverBytesForOneExpectedMessage() throws {
    // Write a message into the buffer:
    let message = ByteBuffer(string: "Hello!")
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = try writer.write(buffer: message, allocator: self.allocator)
    // And some extra junk bytes:
    let bytes: [UInt8] = [0x00]
    buffer.writeBytes(bytes)

    var state: ReadState = .one()
    state.readMessages(&buffer, maxLength: .max).assertFailure {
      XCTAssertEqual($0, .leftOverBytes)
    }
    state.assertNotReading()
  }

  func testReadTooManyMessagesForOneExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = ByteBuffer(string: "Hello!")
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = try writer.write(buffer: message, allocator: self.allocator)
    var second = try writer.write(buffer: message, allocator: self.allocator)
    buffer.writeBuffer(&second)

    var state: ReadState = .one()
    state.readMessages(&buffer, maxLength: .max).assertFailure {
      XCTAssertEqual($0, .cardinalityViolation)
    }
    state.assertNotReading()
  }

  func testReadOneMessageForOneExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = ByteBuffer(string: "Hello!")
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = try writer.write(buffer: message, allocator: self.allocator)

    var state: ReadState = .one()
    state.readMessages(&buffer, maxLength: .max).assertSuccess {
      XCTAssertEqual($0, [message])
    }

    // We shouldn't be able to read anymore.
    state.assertNotReading()
  }

  func testReadOneMessageForManyExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = ByteBuffer(string: "Hello!")
    let writer = LengthPrefixedMessageWriter(compression: .none)
    var buffer = try writer.write(buffer: message, allocator: self.allocator)

    var state: ReadState = .many()
    state.readMessages(&buffer, maxLength: .max).assertSuccess {
      XCTAssertEqual($0, [message])
    }

    // We should still be able to read.
    state.assertReading()
  }

  func testReadManyMessagesForManyExpectedMessages() throws {
    // Write a message into the buffer twice:
    let message = ByteBuffer(string: "Hello!")
    let writer = LengthPrefixedMessageWriter(compression: .none)

    var first = try writer.write(buffer: message, allocator: self.allocator)
    var second = try writer.write(buffer: message, allocator: self.allocator)
    var third = try writer.write(buffer: message, allocator: self.allocator)

    first.writeBuffer(&second)
    first.writeBuffer(&third)

    var state: ReadState = .many()
    state.readMessages(&first, maxLength: .max).assertSuccess {
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
    case let .success(success):
      do {
        try verify(success)
      } catch {
        XCTFail("verify threw: \(error)")
      }
    case let .failure(error):
      XCTFail("unexpected .failure: \(error)")
    }
  }

  /// Asserts the `Result` was a failure.
  func assertFailure(verify: (Failure) throws -> Void = { _ in }) {
    switch self {
    case let .success(success):
      XCTFail("unexpected .success: \(success)")
    case let .failure(error):
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
    let reader = LengthPrefixedMessageReader()
    return .reading(.one, reader)
  }

  static func many() -> ReadState {
    let reader = LengthPrefixedMessageReader()
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
    return .init(arity: .one, contentType: .protobuf)
  }

  static func many() -> PendingWriteState {
    return .init(arity: .many, contentType: .protobuf)
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
