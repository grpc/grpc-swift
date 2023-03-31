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

@testable import GRPC
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest

final class GRPCWebToHTTP2StateMachineTests: GRPCTestCase {
  fileprivate typealias StateMachine = GRPCWebToHTTP2ServerCodec.StateMachine

  private let allocator = ByteBufferAllocator()

  private func makeStateMachine(scheme: String = "http") -> StateMachine {
    return StateMachine(scheme: scheme)
  }

  private func makeRequestHead(
    version: HTTPVersion = .http1_1,
    method: HTTPMethod = .POST,
    uri: String,
    headers: HTTPHeaders = [:]
  ) -> HTTPServerRequestPart {
    return .head(.init(version: version, method: method, uri: uri, headers: headers))
  }

  // MARK: - grpc-web

  func test_gRPCWeb_requestHeaders() {
    var state = self.makeStateMachine(scheme: "http")
    let head = self.makeRequestHead(method: .POST, uri: "foo", headers: ["host": "localhost"])

    let action = state.processInbound(serverRequestPart: head, allocator: self.allocator)
    action.assertRead { payload in
      payload.assertHeaders { payload in
        XCTAssertFalse(payload.endStream)
        XCTAssertEqual(payload.headers[canonicalForm: ":path"], ["foo"])
        XCTAssertEqual(payload.headers[canonicalForm: ":method"], ["POST"])
        XCTAssertEqual(payload.headers[canonicalForm: ":scheme"], ["http"])
        XCTAssertEqual(payload.headers[canonicalForm: ":authority"], ["localhost"])
      }
    }
  }

  func test_gRPCWeb_requestBody() {
    var state = self.makeStateMachine()
    let head = self.makeRequestHead(
      uri: "foo",
      headers: ["content-type": "application/grpc-web"]
    )

    state.processInbound(serverRequestPart: head, allocator: self.allocator).assertRead {
      $0.assertHeaders()
    }

    let b1 = ByteBuffer(string: "hello")
    for _ in 0 ..< 5 {
      state.processInbound(serverRequestPart: .body(b1), allocator: self.allocator).assertRead {
        $0.assertData {
          XCTAssertFalse($0.endStream)
          $0.data.assertByteBuffer { buffer in
            var buffer = buffer
            XCTAssertEqual(buffer.readString(length: buffer.readableBytes), "hello")
          }
        }
      }
    }

    state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead {
      $0.assertEmptyDataWithEndStream()
    }
  }

  private func checkResponseHeaders(
    from state: StateMachine,
    expectConnectionCloseHeader: Bool,
    line: UInt = #line
  ) {
    var state = state
    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "200"])),
      promise: nil,
      allocator: self.allocator
    ).assertWrite { write in
      write.part.assertHead {
        XCTAssertEqual($0.status, .ok, line: line)
        XCTAssertFalse($0.headers.contains(name: ":status"), line: line)

        if expectConnectionCloseHeader {
          XCTAssertEqual($0.headers[canonicalForm: "connection"], ["close"], line: line)
        } else {
          XCTAssertFalse($0.headers.contains(name: "connection"), line: line)
        }
      }
      XCTAssertNil(write.additionalPart, line: line)
      XCTAssertFalse(write.closeChannel, line: line)
    }
  }

  func test_gRPCWeb_responseHeaders() {
    for connectionClose in [true, false] {
      let headers: HTTPHeaders = connectionClose ? ["connection": "close"] : [:]
      let requestHead = self.makeRequestHead(uri: "/echo", headers: headers)

      var state = self.makeStateMachine()
      state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()
      self.checkResponseHeaders(from: state, expectConnectionCloseHeader: connectionClose)

      // Do it again with the request stream closed.
      state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead()
      self.checkResponseHeaders(from: state, expectConnectionCloseHeader: connectionClose)
    }
  }

  private func checkTrailersOnlyResponse(
    from state: StateMachine,
    expectConnectionCloseHeader: Bool,
    line: UInt = #line
  ) {
    var state = state

    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "415"], endStream: true)),
      promise: nil,
      allocator: self.allocator
    ).assertWrite { write in
      write.part.assertHead {
        XCTAssertEqual($0.status, .unsupportedMediaType, line: line)
        XCTAssertFalse($0.headers.contains(name: ":status"), line: line)

        if expectConnectionCloseHeader {
          XCTAssertEqual($0.headers[canonicalForm: "connection"], ["close"], line: line)
        } else {
          XCTAssertFalse($0.headers.contains(name: "connection"), line: line)
        }
      }

      // Should also send end.
      write.additionalPart.assertSome { $0.assertEnd() }
      XCTAssertEqual(write.closeChannel, expectConnectionCloseHeader, line: line)
    }
  }

  func test_gRPCWeb_responseTrailersOnly() {
    for connectionClose in [true, false] {
      let headers: HTTPHeaders = connectionClose ? ["connection": "close"] : [:]
      let requestHead = self.makeRequestHead(uri: "/echo", headers: headers)

      var state = self.makeStateMachine()
      state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()
      self.checkTrailersOnlyResponse(from: state, expectConnectionCloseHeader: connectionClose)

      // Do it again with the request stream closed.
      state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead()
      self.checkTrailersOnlyResponse(from: state, expectConnectionCloseHeader: connectionClose)
    }
  }

  private func checkGRPCWebResponseData(from state: StateMachine, line: UInt = #line) {
    var state = state

    for i in 0 ..< 10 {
      let buffer = ByteBuffer(string: "foo-\(i)")
      state.processOutbound(
        framePayload: .data(.init(data: .byteBuffer(buffer))),
        promise: nil,
        allocator: self.allocator
      ).assertWrite { write in
        write.part.assertBody {
          XCTAssertEqual($0, buffer, line: line)
        }
        XCTAssertNil(write.additionalPart, line: line)
        XCTAssertFalse(write.closeChannel, line: line)
      }
    }
  }

  func test_gRPCWeb_responseData() {
    var state = self.makeStateMachine()
    let requestHead = self.makeRequestHead(
      uri: "/echo",
      headers: ["content-type": "application/grpc-web"]
    )
    state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()
    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "200"])),
      promise: nil,
      allocator: self.allocator
    ).assertWrite()

    // Request stream is open.
    self.checkGRPCWebResponseData(from: state)

    // Close request stream and test again.
    state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead()
    self.checkGRPCWebResponseData(from: state)
  }

  private func checkGRPCWebResponseTrailers(
    from state: StateMachine,
    expectChannelClose: Bool,
    line: UInt = #line
  ) {
    var state = state

    state.processOutbound(
      framePayload: .headers(.init(headers: ["grpc-status": "0"], endStream: true)),
      promise: nil,
      allocator: self.allocator
    ).assertWrite { write in
      write.part.assertBody { buffer in
        var buffer = buffer
        let trailers = buffer.readLengthPrefixedMessage().map { String(buffer: $0) }
        XCTAssertEqual(trailers, "grpc-status: 0\r\n")
      }
      XCTAssertEqual(write.closeChannel, expectChannelClose)
    }
  }

  func test_gRPCWeb_responseTrailers() {
    for connectionClose in [true, false] {
      let headers: HTTPHeaders = connectionClose ? ["connection": "close"] : [:]
      let requestHead = self.makeRequestHead(uri: "/echo", headers: headers)

      var state = self.makeStateMachine()
      state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()
      state.processOutbound(
        framePayload: .headers(.init(headers: [":status": "200"])),
        promise: nil,
        allocator: self.allocator
      ).assertWrite()

      // Request stream is open.
      self.checkGRPCWebResponseTrailers(from: state, expectChannelClose: connectionClose)

      // Check again with request stream closed.
      state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead()
      self.checkGRPCWebResponseTrailers(from: state, expectChannelClose: connectionClose)
    }
  }

  // MARK: - grpc-web-text

  func test_gRPCWebText_requestBody() {
    var state = self.makeStateMachine()
    let head = self.makeRequestHead(
      uri: "foo",
      headers: ["content-type": "application/grpc-web-text"]
    )

    state.processInbound(serverRequestPart: head, allocator: self.allocator).assertRead {
      $0.assertHeaders()
    }

    let expected = ["hel", "lo"]
    let buffers = [ByteBuffer(string: "aGVsb"), ByteBuffer(string: "G8=")]

    for (buffer, expected) in zip(buffers, expected) {
      state.processInbound(serverRequestPart: .body(buffer), allocator: self.allocator).assertRead {
        $0.assertData {
          XCTAssertFalse($0.endStream)
          $0.data.assertByteBuffer { buffer in
            var buffer = buffer
            XCTAssertEqual(buffer.readString(length: buffer.readableBytes), expected)
          }
        }
      }
    }

    // If there's not enough to decode, there's nothing to do.
    let buffer = ByteBuffer(string: "a")
    state.processInbound(serverRequestPart: .body(buffer), allocator: self.allocator).assertNone()

    state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead {
      $0.assertEmptyDataWithEndStream()
    }
  }

  private func checkResponseDataAndTrailersForGRPCWebText(
    from state: StateMachine,
    line: UInt = #line
  ) {
    var state = state

    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "200"])),
      promise: nil,
      allocator: self.allocator
    ).assertWrite()

    // Write some bytes.
    for text in ["hello", ", world!"] {
      let buffer = ByteBuffer(string: text)
      state.processOutbound(
        framePayload: .data(.init(data: .byteBuffer(buffer))),
        promise: nil,
        allocator: self.allocator
      ).assertCompletePromise { error in
        XCTAssertNil(error)
      }
    }

    state.processOutbound(
      framePayload: .headers(.init(headers: ["grpc-status": "0"], endStream: true)),
      promise: nil,
      allocator: self.allocator
    ).assertWrite { write in
      // The response is encoded by:
      // - accumulating the bytes of request messages (these would normally be gRPC length prefixed
      //   messages)
      // - appending a 'trailers' byte (0x80)
      // - appending the UInt32 length of the trailers when encoded as HTTP/1 header lines
      // - the encoded headers
      write.part.assertBody { buffer in
        var buffer = buffer
        let base64Encoded = buffer.readString(length: buffer.readableBytes)!
        XCTAssertEqual(base64Encoded, "aGVsbG8sIHdvcmxkIYAAAAAQZ3JwYy1zdGF0dXM6IDANCg==")

        let data = Data(base64Encoded: base64Encoded)!
        buffer.writeData(data)

        XCTAssertEqual(buffer.readString(length: 13), "hello, world!")
        XCTAssertEqual(buffer.readInteger(), UInt8(0x80))
        XCTAssertEqual(buffer.readInteger(), UInt32(16))
        XCTAssertEqual(buffer.readString(length: 16), "grpc-status: 0\r\n")
        XCTAssertEqual(buffer.readableBytes, 0)
      }

      // There should be an end now.
      write.additionalPart.assertSome { $0.assertEnd() }

      XCTAssertFalse(write.closeChannel)
    }
  }

  func test_gRPCWebText_responseDataAndTrailers() {
    var state = self.makeStateMachine()
    let requestHead = self.makeRequestHead(
      uri: "/echo",
      headers: ["content-type": "application/grpc-web-text"]
    )
    state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()

    // Request stream is still open.
    self.checkResponseDataAndTrailersForGRPCWebText(from: state)

    // Check again with request stream closed.
    state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead()
    self.checkResponseDataAndTrailersForGRPCWebText(from: state)
  }

  // MARK: - General

  func test_requestPartsAfterServerClosed() {
    var state = self.makeStateMachine()
    let requestHead = self.makeRequestHead(uri: "/echo")
    state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()

    // Close the response stream.
    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "415"], endStream: true)),
      promise: nil,
      allocator: self.allocator
    ).assertWrite()

    state.processInbound(
      serverRequestPart: .body(ByteBuffer(string: "hello world")),
      allocator: self.allocator
    ).assertRead {
      $0.assertData {
        XCTAssertFalse($0.endStream)
        $0.data.assertByteBuffer { buffer in
          XCTAssertTrue(buffer.readableBytesView.elementsEqual("hello world".utf8))
        }
      }
    }
    state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator).assertRead {
      $0.assertEmptyDataWithEndStream()
    }
  }

  func test_responsePartsAfterServerClosed() {
    var state = self.makeStateMachine()
    let requestHead = self.makeRequestHead(uri: "/echo")
    state.processInbound(serverRequestPart: requestHead, allocator: self.allocator).assertRead()

    // Close the response stream.
    state.processOutbound(
      framePayload: .headers(.init(headers: [":status": "415"], endStream: true)),
      promise: nil,
      allocator: self.allocator
    ).assertWrite()

    // More writes should be told to fail their promise.
    state.processOutbound(
      framePayload: .headers(.init(headers: .init())), promise: nil, allocator: self.allocator
    ).assertCompletePromise { error in
      XCTAssertNotNil(error)
    }

    state.processOutbound(
      framePayload: .data(.init(data: .byteBuffer(.init()))),
      promise: nil,
      allocator: self.allocator
    ).assertCompletePromise { error in
      XCTAssertNotNil(error)
    }
  }

  func test_handleMultipleRequests() {
    func sendRequestHead(_ state: inout StateMachine, contentType: ContentType) -> StateMachine
      .Action {
      let requestHead = self.makeRequestHead(
        uri: "/echo", headers: ["content-type": contentType.canonicalValue]
      )
      return state.processInbound(serverRequestPart: requestHead, allocator: self.allocator)
    }

    func sendRequestBody(_ state: inout StateMachine, buffer: ByteBuffer) -> StateMachine.Action {
      return state.processInbound(serverRequestPart: .body(buffer), allocator: self.allocator)
    }

    func sendRequestEnd(_ state: inout StateMachine) -> StateMachine.Action {
      return state.processInbound(serverRequestPart: .end(nil), allocator: self.allocator)
    }

    func sendResponseHeaders(
      _ state: inout StateMachine,
      headers: HPACKHeaders,
      endStream: Bool = false
    ) -> StateMachine.Action {
      return state.processOutbound(
        framePayload: .headers(.init(headers: headers, endStream: endStream)),
        promise: nil,
        allocator: self.allocator
      )
    }

    func sendResponseData(
      _ state: inout StateMachine,
      buffer: ByteBuffer
    ) -> StateMachine.Action {
      return state.processOutbound(
        framePayload: .data(.init(data: .byteBuffer(buffer))),
        promise: nil,
        allocator: self.allocator
      )
    }

    var state = self.makeStateMachine()

    // gRPC-Web, all request parts then all response parts.
    sendRequestHead(&state, contentType: .webProtobuf).assertRead()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendRequestEnd(&state).assertRead()
    sendResponseHeaders(&state, headers: [":status": "200"]).assertWrite()
    sendResponseData(&state, buffer: .init(string: "bye")).assertWrite()
    sendResponseHeaders(&state, headers: ["grpc-status": "0"], endStream: true).assertWrite()

    // gRPC-Web text, all requests then all response parts.
    sendRequestHead(&state, contentType: .webTextProtobuf).assertRead()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendRequestEnd(&state).assertRead()
    sendResponseHeaders(&state, headers: [":status": "200"]).assertWrite()
    // nothing; buffered and sent with end.
    sendResponseData(&state, buffer: .init(string: "bye")).assertCompletePromise()
    sendResponseHeaders(&state, headers: ["grpc-status": "0"], endStream: true).assertWrite()

    // gRPC-Web, interleaving
    sendRequestHead(&state, contentType: .webProtobuf).assertRead()
    sendResponseHeaders(&state, headers: [":status": "200"]).assertWrite()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendResponseData(&state, buffer: .init(string: "bye")).assertWrite()
    sendRequestEnd(&state).assertRead()
    sendResponseHeaders(&state, headers: ["grpc-status": "0"], endStream: true).assertWrite()

    // gRPC-Web text, interleaving
    sendRequestHead(&state, contentType: .webTextProtobuf).assertRead()
    sendResponseHeaders(&state, headers: [":status": "200"]).assertWrite()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendResponseData(&state, buffer: .init(string: "bye")).assertCompletePromise()
    sendRequestEnd(&state).assertRead()
    sendResponseHeaders(&state, headers: ["grpc-status": "0"], endStream: true).assertWrite()

    // gRPC-Web, server closes immediately.
    sendRequestHead(&state, contentType: .webProtobuf).assertRead()
    sendResponseHeaders(&state, headers: [":status": "415"], endStream: true).assertWrite()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendRequestEnd(&state).assertRead()

    // gRPC-Web text, server closes immediately.
    sendRequestHead(&state, contentType: .webTextProtobuf).assertRead()
    sendResponseHeaders(&state, headers: [":status": "415"], endStream: true).assertWrite()
    sendRequestBody(&state, buffer: .init(string: "hello")).assertRead()
    sendRequestEnd(&state).assertRead()
  }
}

// MARK: - Assertions

extension GRPCWebToHTTP2ServerCodec.StateMachine.Action {
  func assertRead(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (HTTP2Frame.FramePayload) -> Void = { _ in }
  ) {
    if case let .fireChannelRead(payload) = self {
      verify(payload)
    } else {
      XCTFail("Expected '.fireChannelRead' but got '\(self)'", file: file, line: line)
    }
  }

  func assertWrite(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Write) -> Void = { _ in }
  ) {
    if case let .write(write) = self {
      verify(write)
    } else {
      XCTFail("Expected '.write' but got '\(self)'", file: file, line: line)
    }
  }

  func assertCompletePromise(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Error?) -> Void = { _ in }
  ) {
    if case let .completePromise(_, result) = self {
      do {
        try result.get()
        verify(nil)
      } catch {
        verify(error)
      }
    } else {
      XCTFail("Expected '.completePromise' but got '\(self)'", file: file, line: line)
    }
  }

  func assertNone(
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    if case .none = self {
      ()
    } else {
      XCTFail("Expected '.none' but got '\(self)'", file: file, line: line)
    }
  }
}

extension HTTP2Frame.FramePayload {
  func assertHeaders(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Headers) -> Void = { _ in }
  ) {
    if case let .headers(headers) = self {
      verify(headers)
    } else {
      XCTFail("Expected '.headers' but got '\(self)'", file: file, line: line)
    }
  }

  func assertData(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Data) -> Void = { _ in }
  ) {
    if case let .data(data) = self {
      verify(data)
    } else {
      XCTFail("Expected '.data' but got '\(self)'", file: file, line: line)
    }
  }

  func assertEmptyDataWithEndStream(
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    self.assertData(file: file, line: line) {
      XCTAssertTrue($0.endStream)
      $0.data.assertByteBuffer { buffer in
        XCTAssertEqual(buffer.readableBytes, 0)
      }
    }
  }
}

extension HTTPServerResponsePart {
  func assertHead(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (HTTPResponseHead) -> Void = { _ in }
  ) {
    if case let .head(head) = self {
      verify(head)
    } else {
      XCTFail("Expected '.head' but got '\(self)'", file: file, line: line)
    }
  }

  func assertBody(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (ByteBuffer) -> Void = { _ in }
  ) {
    if case let .body(.byteBuffer(buffer)) = self {
      verify(buffer)
    } else {
      XCTFail("Expected '.body(.byteBuffer)' but got '\(self)'", file: file, line: line)
    }
  }

  func assertEnd(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (HTTPHeaders?) -> Void = { _ in }
  ) {
    if case let .end(trailers) = self {
      verify(trailers)
    } else {
      XCTFail("Expected '.end' but got '\(self)'", file: file, line: line)
    }
  }
}

extension IOData {
  func assertByteBuffer(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (ByteBuffer) -> Void = { _ in }
  ) {
    if case let .byteBuffer(buffer) = self {
      verify(buffer)
    } else {
      XCTFail("Expected '.byteBuffer' but got '\(self)'", file: file, line: line)
    }
  }
}

extension Optional {
  func assertSome(
    file: StaticString = #filePath,
    line: UInt = #line,
    verify: (Wrapped) -> Void = { _ in }
  ) {
    switch self {
    case let .some(wrapped):
      verify(wrapped)
    case .none:
      XCTFail("Expected '.some' but got 'nil'", file: file, line: line)
    }
  }
}

extension ByteBuffer {
  mutating func readLengthPrefixedMessage() -> ByteBuffer? {
    // Read off and ignore the compression byte.
    if self.readInteger(as: UInt8.self) == nil {
      return nil
    }

    return self.readLengthPrefixedSlice(as: UInt32.self)
  }
}
