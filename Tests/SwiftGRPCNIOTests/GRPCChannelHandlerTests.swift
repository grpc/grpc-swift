import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import SwiftGRPCNIO

class GRPCChannelHandlerTests: GRPCChannelHandlerResponseCapturingTestCase {
  static var allTests: [(String, (GRPCChannelHandlerTests) -> () throws -> Void)] {
    return [
      ("testUnimplementedMethodReturnsUnimplementedStatus", testUnimplementedMethodReturnsUnimplementedStatus),
      ("testImplementedMethodReturnsHeadersMessageAndStatus", testImplementedMethodReturnsHeadersMessageAndStatus),
      ("testImplementedMethodReturnsStatusForBadlyFormedProto", testImplementedMethodReturnsStatusForBadlyFormedProto),
    ]
  }

  func testUnimplementedMethodReturnsUnimplementedStatus() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 1) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "unimplementedMethodName")
      try channel.writeInbound(RawGRPCServerRequestPart.head(requestHead))
    }

    let expectedError = GRPCServerError.unimplementedMethod("unimplementedMethodName")
    XCTAssertEqual([expectedError], errorCollector.asGRPCServerErrors)

    XCTAssertNoThrow(try extractStatus(responses[0])) { status in
      XCTAssertEqual(status, expectedError.asGRPCStatus())
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
      XCTAssertEqual(status, .ok)
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

    let expectedError = GRPCServerError.requestProtoDeserializationFailure
    XCTAssertEqual([expectedError], errorCollector.asGRPCServerErrors)

    XCTAssertNoThrow(try extractHeaders(responses[0]))
    XCTAssertNoThrow(try extractStatus(responses[1])) { status in
      XCTAssertEqual(status, expectedError.asGRPCStatus())
    }
  }
}
