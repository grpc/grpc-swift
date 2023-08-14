/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import struct Foundation.Data
@testable import GRPC
import NIOCore
import NIOEmbedded
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest

class GRPCWebToHTTP2ServerCodecTests: GRPCTestCase {
  private func writeTrailers(_ trailers: HPACKHeaders, into buffer: inout ByteBuffer) {
    buffer.writeInteger(UInt8(0x80))
    try! buffer.writeLengthPrefixed(as: UInt32.self) {
      var length = 0
      for (name, value, _) in trailers {
        length += $0.writeString("\(name): \(value)\r\n")
      }
      return length
    }
  }

  private func receiveHead(
    contentType: ContentType,
    path: String,
    on channel: EmbeddedChannel
  ) throws {
    let head = HTTPRequestHead(
      version: .init(major: 1, minor: 1),
      method: .POST,
      uri: path,
      headers: [GRPCHeaderName.contentType: contentType.canonicalValue]
    )
    assertThat(try channel.writeInbound(HTTPServerRequestPart.head(head)), .doesNotThrow())
    let headersPayload = try channel.readInbound(as: HTTP2Frame.FramePayload.self)
    assertThat(headersPayload, .some(.headers(.contains(":path", [path]))))
  }

  private func receiveBytes(
    _ buffer: ByteBuffer,
    on channel: EmbeddedChannel,
    expectedBytes: [UInt8]? = nil
  ) throws {
    assertThat(try channel.writeInbound(HTTPServerRequestPart.body(buffer)), .doesNotThrow())

    if let expectedBytes = expectedBytes {
      let dataPayload = try channel.readInbound(as: HTTP2Frame.FramePayload.self)
      assertThat(dataPayload, .some(.data(buffer: ByteBuffer(bytes: expectedBytes))))
    }
  }

  private func receiveEnd(on channel: EmbeddedChannel) throws {
    assertThat(try channel.writeInbound(HTTPServerRequestPart.end(nil)), .doesNotThrow())
    let dataEndPayload = try channel.readInbound(as: HTTP2Frame.FramePayload.self)
    assertThat(dataEndPayload, .some(.data(buffer: ByteBuffer(), endStream: true)))
  }

  private func sendResponseHeaders(on channel: EmbeddedChannel) throws {
    let responseHeaders: HPACKHeaders = [":status": "200"]
    let headerPayload: HTTP2Frame.FramePayload = .headers(.init(headers: responseHeaders))
    assertThat(try channel.writeOutbound(headerPayload), .doesNotThrow())
    let responseHead = try channel.readOutbound(as: HTTPServerResponsePart.self)
    assertThat(responseHead, .some(.head(status: .ok)))
  }

  private func sendTrailersOnlyResponse(on channel: EmbeddedChannel) throws {
    let headers: HPACKHeaders = [":status": "200"]
    let headerPayload: HTTP2Frame.FramePayload = .headers(.init(headers: headers, endStream: true))

    assertThat(try channel.writeOutbound(headerPayload), .doesNotThrow())
    let responseHead = try channel.readOutbound(as: HTTPServerResponsePart.self)
    assertThat(responseHead, .some(.head(status: .ok)))
    let end = try channel.readOutbound(as: HTTPServerResponsePart.self)
    assertThat(end, .some(.end()))
  }

  private func sendBytes(
    _ bytes: [UInt8],
    on channel: EmbeddedChannel,
    expectedBytes: [UInt8]? = nil
  ) throws {
    let responseBuffer = ByteBuffer(bytes: bytes)
    let dataPayload: HTTP2Frame.FramePayload = .data(.init(data: .byteBuffer(responseBuffer)))
    assertThat(try channel.writeOutbound(dataPayload), .doesNotThrow())

    if let expectedBytes = expectedBytes {
      let expectedBuffer = ByteBuffer(bytes: expectedBytes)
      assertThat(try channel.readOutbound(), .some(.body(.is(expectedBuffer))))
    } else {
      assertThat(try channel.readOutbound(as: HTTPServerResponsePart.self), .doesNotThrow(.none()))
    }
  }

  private func sendEnd(
    status: GRPCStatus.Code,
    on channel: EmbeddedChannel,
    expectedBytes: ByteBuffer? = nil
  ) throws {
    let headers: HPACKHeaders = ["grpc-status": "\(status.rawValue)"]
    let headersPayload: HTTP2Frame.FramePayload = .headers(.init(headers: headers, endStream: true))
    assertThat(try channel.writeOutbound(headersPayload), .doesNotThrow())

    if let expectedBytes = expectedBytes {
      assertThat(try channel.readOutbound(), .some(.body(.is(expectedBytes))))
    }

    assertThat(try channel.readOutbound(), .some(.end()))
  }

  func testWebBinaryHappyPath() throws {
    let channel = EmbeddedChannel(handler: GRPCWebToHTTP2ServerCodec(scheme: "http"))

    // Inbound
    try self.receiveHead(contentType: .webProtobuf, path: "foo", on: channel)
    try self.receiveBytes(ByteBuffer(bytes: [1, 2, 3]), on: channel, expectedBytes: [1, 2, 3])
    try self.receiveEnd(on: channel)

    // Outbound
    try self.sendResponseHeaders(on: channel)
    try self.sendBytes([1, 2, 3], on: channel, expectedBytes: [1, 2, 3])

    var buffer = ByteBuffer()
    self.writeTrailers(["grpc-status": "0"], into: &buffer)
    try self.sendEnd(status: .ok, on: channel, expectedBytes: buffer)
  }

  func testWebTextHappyPath() throws {
    let channel = EmbeddedChannel(handler: GRPCWebToHTTP2ServerCodec(scheme: "http"))

    // Inbound
    try self.receiveHead(contentType: .webTextProtobuf, path: "foo", on: channel)
    try self.receiveBytes(
      ByteBuffer(bytes: [1, 2, 3]).base64Encoded(),
      on: channel,
      expectedBytes: [1, 2, 3]
    )
    try self.receiveEnd(on: channel)

    // Outbound
    try self.sendResponseHeaders(on: channel)
    try self.sendBytes([1, 2, 3], on: channel)

    // Build up the expected response, i.e. the response bytes and the trailers, base64 encoded.
    var expectedBodyBuffer = ByteBuffer(bytes: [1, 2, 3])
    let status = GRPCStatus.Code.ok
    self.writeTrailers(["grpc-status": "\(status.rawValue)"], into: &expectedBodyBuffer)
    try self.sendEnd(status: status, on: channel, expectedBytes: expectedBodyBuffer.base64Encoded())
  }

  func testWebTextStatusOnlyResponse() throws {
    let channel = EmbeddedChannel(handler: GRPCWebToHTTP2ServerCodec(scheme: "http"))

    try self.receiveHead(contentType: .webTextProtobuf, path: "foo", on: channel)
    try self.sendTrailersOnlyResponse(on: channel)
  }

  func testWebTextByteByByte() throws {
    let channel = EmbeddedChannel(handler: GRPCWebToHTTP2ServerCodec(scheme: "http"))

    try self.receiveHead(contentType: .webTextProtobuf, path: "foo", on: channel)

    let bytes = ByteBuffer(bytes: [1, 2, 3]).base64Encoded()
    try self.receiveBytes(bytes.getSlice(at: 0, length: 1)!, on: channel, expectedBytes: nil)
    try self.receiveBytes(bytes.getSlice(at: 1, length: 1)!, on: channel, expectedBytes: nil)
    try self.receiveBytes(bytes.getSlice(at: 2, length: 1)!, on: channel, expectedBytes: nil)
    try self.receiveBytes(bytes.getSlice(at: 3, length: 1)!, on: channel, expectedBytes: [1, 2, 3])
  }

  func testSendAfterEnd() throws {
    let channel = EmbeddedChannel(handler: GRPCWebToHTTP2ServerCodec(scheme: "http"))
    // Get to a closed state.
    try self.receiveHead(contentType: .webTextProtobuf, path: "foo", on: channel)
    try self.sendTrailersOnlyResponse(on: channel)

    let headersPayload: HTTP2Frame.FramePayload = .headers(.init(headers: [:]))
    assertThat(try channel.write(headersPayload).wait(), .throws())

    let dataPayload: HTTP2Frame.FramePayload = .data(.init(data: .byteBuffer(.init())))
    assertThat(try channel.write(dataPayload).wait(), .throws())
  }
}

extension ByteBuffer {
  fileprivate func base64Encoded() -> ByteBuffer {
    let data = self.getData(at: self.readerIndex, length: self.readableBytes)!
    return ByteBuffer(string: data.base64EncodedString())
  }
}
