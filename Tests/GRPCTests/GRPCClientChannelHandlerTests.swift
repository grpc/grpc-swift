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

import NIOCore
import NIOEmbedded
import NIOHPACK
import NIOHTTP2
import XCTest

@testable import GRPC

class GRPCClientChannelHandlerTests: GRPCTestCase {
  private func makeRequestHead() -> _GRPCRequestHead {
    return _GRPCRequestHead(
      method: "POST",
      scheme: "https",
      path: "/foo/bar",
      host: "localhost",
      deadline: .distantFuture,
      customMetadata: [:],
      encoding: .disabled
    )
  }

  func doTestDataFrameWithEndStream(dataContainsMessage: Bool) throws {
    let handler = GRPCClientChannelHandler(
      callType: .unary,
      maximumReceiveMessageLength: .max,
      logger: self.clientLogger
    )

    let channel = EmbeddedChannel(handler: handler)

    // Write request head.
    let head = self.makeRequestHead()
    XCTAssertNoThrow(try channel.writeOutbound(_RawGRPCClientRequestPart.head(head)))
    // Read out a frame payload.
    XCTAssertNotNil(try channel.readOutbound(as: HTTP2Frame.FramePayload.self))

    // Respond with headers.
    let headers: HPACKHeaders = [":status": "200", "content-type": "application/grpc"]
    let headersPayload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
    XCTAssertNoThrow(try channel.writeInbound(headersPayload))
    // Read them out the other side.
    XCTAssertNotNil(try channel.readInbound(as: _RawGRPCClientResponsePart.self))

    // Respond with DATA and end stream.
    var buffer = ByteBuffer()

    // Write a message, if we need to.
    if dataContainsMessage {
      buffer.writeInteger(UInt8(0))  // not compressed
      buffer.writeInteger(UInt32(42))  // message length
      buffer.writeRepeatingByte(0, count: 42)  // message
    }

    let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(buffer), endStream: true)
    XCTAssertNoThrow(try channel.writeInbound(HTTP2Frame.FramePayload.data(dataPayload)))

    if dataContainsMessage {
      // Read the message out the other side.
      XCTAssertNotNil(try channel.readInbound(as: _RawGRPCClientResponsePart.self))
    }

    // We should also generate a status since end stream was set.
    if let part = try channel.readInbound(as: _RawGRPCClientResponsePart.self) {
      switch part {
      case .initialMetadata, .message, .trailingMetadata:
        XCTFail("Unexpected response part")
      case .status:
        ()  // Expected
      }
    } else {
      XCTFail("Expected to read another response part")
    }
  }

  func testDataFrameWithEndStream() throws {
    try self.doTestDataFrameWithEndStream(dataContainsMessage: true)
  }

  func testEmptyDataFrameWithEndStream() throws {
    try self.doTestDataFrameWithEndStream(dataContainsMessage: false)
  }
}
