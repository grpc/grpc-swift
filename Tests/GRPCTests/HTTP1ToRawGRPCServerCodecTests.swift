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
import XCTest
import NIO
import NIOHTTP1
@testable import GRPC
import Logging

func gRPCMessage(channel: EmbeddedChannel, compression: Bool = false, message: Data? = nil) -> ByteBuffer {
  let messageLength = message?.count ?? 0
  var buffer = channel.allocator.buffer(capacity: 5 + messageLength)
  buffer.writeInteger(Int8(compression ? 1 : 0))
  buffer.writeInteger(UInt32(messageLength))
  if let bytes = message {
    buffer.writeBytes(bytes)
  }
  return buffer
}

class HTTP1ToRawGRPCServerCodecTests: GRPCChannelHandlerResponseCapturingTestCase {
  func testInternalErrorStatusReturnedWhenCompressionFlagIsSet() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
      try channel.writeInbound(HTTPServerRequestPart.body(gRPCMessage(channel: channel, compression: true)))
    }

    let expectedError = GRPCCommonError.unexpectedCompression
    XCTAssertEqual([expectedError], errorCollector.asGRPCCommonErrors)

    responses[0].assertHeaders()
    responses[1].assertStatus { status in
      assertEqualStatusIgnoringTrailers(status, expectedError.asGRPCStatus())
    }
  }

  func testMessageCanBeSentAcrossMultipleByteBuffers() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 3) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      // Sending the header allocates a buffer.
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))

      let request = Echo_EchoRequest.with { $0.text = "echo!" }
      let requestAsData = try request.serializedData()

      var buffer = channel.allocator.buffer(capacity: 1)
      buffer.writeInteger(Int8(0))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))

      buffer = channel.allocator.buffer(capacity: 4)
      buffer.writeInteger(Int32(requestAsData.count))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))

      buffer = channel.allocator.buffer(capacity: requestAsData.count)
      buffer.writeBytes(requestAsData)
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))
    }

    responses[0].assertHeaders()
    responses[1].assertMessage()
    responses[2].assertStatus { status in
      assertEqualStatusIgnoringTrailers(status, .ok)
    }
  }

  func testInternalErrorStatusIsReturnedIfMessageCannotBeDeserialized() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))

      let buffer = gRPCMessage(channel: channel, message: Data([42]))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))
    }

    let expectedError = GRPCServerError.requestProtoDeserializationFailure
    XCTAssertEqual([expectedError], errorCollector.asGRPCServerErrors)

    responses[0].assertHeaders()
    responses[1].assertStatus { status in
      assertEqualStatusIgnoringTrailers(status, expectedError.asGRPCStatus())
    }
  }

  func testInternalErrorStatusIsReturnedWhenSendingTrailersInRequest() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      // We have to use "Collect" (client streaming) as the tests rely on `EmbeddedChannel` which runs in this thread.
      // In the current server implementation, responses from unary calls send a status immediately after sending the response.
      // As such, a unary "Get" would return an "ok" status before the trailers would be sent.
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Collect")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
      try channel.writeInbound(HTTPServerRequestPart.body(gRPCMessage(channel: channel)))

      var trailers = HTTPHeaders()
      trailers.add(name: "foo", value: "bar")
      try channel.writeInbound(HTTPServerRequestPart.end(trailers))
    }

    XCTAssertEqual(errorCollector.errors.count, 1)

    if case .some(.invalidState(let message)) = errorCollector.asGRPCCommonErrors?.first {
      XCTAssert(message.contains("trailers"))
    } else {
      XCTFail("\(String(describing: errorCollector.errors.first)) was not .invalidState")
    }

    responses[0].assertHeaders()
    responses[1].assertStatus { status in
      assertEqualStatusIgnoringTrailers(status, .processingError)
    }
  }

  func testOnlyOneStatusIsReturned() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 3) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
      try channel.writeInbound(HTTPServerRequestPart.body(gRPCMessage(channel: channel)))

      // Sending trailers with `.end` should trigger an error. However, writing a message to a unary call
      // will trigger a response and status to be sent back. Since we're using `EmbeddedChannel` this will
      // be done before the trailers are sent. If a 4th resposne were to be sent (for the error status) then
      // the test would fail.

      var trailers = HTTPHeaders()
      trailers.add(name: "foo", value: "bar")
      try channel.writeInbound(HTTPServerRequestPart.end(trailers))
    }

    responses[0].assertHeaders()
    responses[1].assertMessage()
    responses[2].assertStatus { status in
      assertEqualStatusIgnoringTrailers(status, .ok)
    }
  }

  override func waitForGRPCChannelHandlerResponses(
    count: Int,
    servicesByName: [String: CallHandlerProvider] = GRPCChannelHandlerResponseCapturingTestCase.echoProvider,
    callback: @escaping (EmbeddedChannel) throws -> Void
    ) throws -> [RawGRPCServerResponsePart] {
    return try super.waitForGRPCChannelHandlerResponses(count: count, servicesByName: servicesByName) { channel in
      _ = channel.pipeline.addHandlers(HTTP1ToRawGRPCServerCodec(logger: Logger(label: "io.grpc.testing")), position: .first)
        .flatMapThrowing { _ in try callback(channel) }
    }
  }
}
