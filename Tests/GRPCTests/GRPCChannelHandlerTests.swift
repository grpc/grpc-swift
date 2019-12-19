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
import EchoModel

class GRPCChannelHandlerTests: GRPCChannelHandlerResponseCapturingTestCase {
  func testUnimplementedMethodReturnsUnimplementedStatus() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 1) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "unimplementedMethodName")
      try channel.writeInbound(_RawGRPCServerRequestPart.head(requestHead))
    }

    let expectedError = GRPCServerError.unimplementedMethod("unimplementedMethodName")
    XCTAssertEqual([expectedError], errorCollector.asGRPCServerErrors)

    responses[0].assertStatus { status in
      XCTAssertEqual(status, expectedError.asGRPCStatus())
    }
  }

  func testImplementedMethodReturnsHeadersMessageAndStatus() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 3) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(_RawGRPCServerRequestPart.head(requestHead))

      let request = Echo_EchoRequest.with { $0.text = "echo!" }
      let requestData = try request.serializedData()
      var buffer = channel.allocator.buffer(capacity: requestData.count)
      buffer.writeBytes(requestData)
      try channel.writeInbound(_RawGRPCServerRequestPart.message(buffer))
    }

    responses[0].assertHeaders()
    responses[1].assertMessage()
    responses[2].assertStatus { status in
      XCTAssertEqual(status.code, .ok)
    }
  }

  func testImplementedMethodReturnsStatusForBadlyFormedProto() throws {
    let responses = try waitForGRPCChannelHandlerResponses(count: 2) { channel in
      let requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: "/echo.Echo/Get")
      try channel.writeInbound(_RawGRPCServerRequestPart.head(requestHead))

      var buffer = channel.allocator.buffer(capacity: 3)
      buffer.writeBytes([1, 2, 3])
      try channel.writeInbound(_RawGRPCServerRequestPart.message(buffer))
    }

    let expectedError = GRPCServerError.requestProtoDeserializationFailure
    XCTAssertEqual([expectedError], errorCollector.asGRPCServerErrors)

    responses[0].assertHeaders()
    responses[1].assertStatus { status in
      XCTAssertEqual(status, expectedError.asGRPCStatus())
    }
  }
}
