import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import SwiftGRPCNIO

func gRPCMessage(channel: EmbeddedChannel, compression: Bool = false, message: Data? = nil) -> ByteBuffer {
  let messageLength = message?.count ?? 0
  var buffer = channel.allocator.buffer(capacity: 5 + messageLength)
  buffer.write(integer: Int8(compression ? 1 : 0))
  buffer.write(integer: UInt32(messageLength))
  if let bytes = message {
    buffer.write(bytes: bytes)
  }
  return buffer
}

class GRPCChannelHandlerTests: GRPCChannelHandlerResponseCapturingTestCase {
  func testUnimplementedMethodReturnsUnimplementedStatus() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 1) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "unimplemented")
      try channel.writeInbound(RawGRPCServerRequestPart.head(requestHead))
    }

    XCTAssertNoThrow(try extractStatus(responses[0])) { status in
      XCTAssertEqual(status.code, .unimplemented)
    }
  }

  func testImplementedMethodReturnsHeadersMessageAndStatus() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 3) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(RawGRPCServerRequestPart.head(requestHead))

      let request = Echo_EchoRequest.with { $0.text = "echo!" }
      let requestData = try request.serializedData()
      var buffer = channel.allocator.buffer(capacity: requestData.count)
      buffer.write(bytes: requestData)
      try channel.writeInbound(RawGRPCServerRequestPart.message(buffer))
    }

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractMessage(responses[1]))
    XCTAssertNoThrow(try extractStatus(responses[2])) { status in
      XCTAssertEqual(status.code, .ok)
    }
  }

  func testImplementedMethodReturnsStatusForBadlyFormedProto() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(RawGRPCServerRequestPart.head(requestHead))

      var buffer = channel.allocator.buffer(capacity: 3)
      buffer.write(bytes: [1, 2, 3])
      try channel.writeInbound(RawGRPCServerRequestPart.message(buffer))
    }

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractStatus(responses[1])) { status in
      let expectedStatus = GRPCStatus.requestProtoParseError
      XCTAssertEqual(status.code, expectedStatus.code)
      XCTAssertEqual(status.message, expectedStatus.message)
    }
  }
}

class HTTP1ToRawGRPCServerCodecTests: GRPCChannelHandlerResponseCapturingTestCase {
  func testUnimplementedStatusReturnedWhenCompressionFlagIsSet() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
      try channel.writeInbound(HTTPServerRequestPart.body(gRPCMessage(channel: channel, compression: true)))
    }

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractStatus(responses[1])) { status in
      let expected = GRPCStatus.unsupportedCompression
      XCTAssertEqual(status.code, expected.code)
      XCTAssertEqual(status.message, expected.message)
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
      buffer.write(integer: Int8(0))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))

      buffer = channel.allocator.buffer(capacity: 4)
      buffer.write(integer: Int32(requestAsData.count))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))

      buffer = channel.allocator.buffer(capacity: requestAsData.count)
      buffer.write(bytes: requestAsData)
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))
    }

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractMessage(responses[1]))
    XCTAssertNoThrow(try extractStatus(responses[2])) { status in
      XCTAssertEqual(status.code, .ok)
    }
  }

  func testInternalErrorStatusIsReturnedIfMessageCannotBeDeserialized() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(HTTPServerRequestPart.head(requestHead))

      let buffer = gRPCMessage(channel: channel, message: Data(bytes: [42]))
      try channel.writeInbound(HTTPServerRequestPart.body(buffer))
    }

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractStatus(responses[1])) { status in
      let expected = GRPCStatus.requestProtoParseError
      XCTAssertEqual(status.code, expected.code)
      XCTAssertEqual(status.message, expected.message)
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

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractStatus(responses[1])) { status in
      XCTAssertEqual(status.code, .internalError)
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

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractMessage(responses[1]))
    XCTAssertNoThrow(try extractStatus(responses[2])) { status in
      XCTAssertEqual(status.code, .ok)
    }
  }

  override func waitForGRPCChannelHandlerResponses(
    count: Int,
    servicesByName: [String: CallHandlerProvider] = GRPCChannelHandlerResponseCapturingTestCase.echoProvider,
    callback: @escaping (EmbeddedChannel) throws -> Void
  ) throws -> [RawGRPCServerResponsePart] {
    return try super.waitForGRPCChannelHandlerResponses(count: count, servicesByName: servicesByName) { channel in
      _ = channel.pipeline.addHandlers(HTTP1ToRawGRPCServerCodec(), first: true)
        .thenThrowing { _ in try callback(channel) }
    }
  }
}

// Assert the given expression does not throw, and validate the return value from that expression.
public func XCTAssertNoThrow<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line,
    validate: (T) -> Void
) {
  var value: T? = nil
  XCTAssertNoThrow(try value = expression(), message, file: file, line: line)
  value.map { validate($0) }
}
