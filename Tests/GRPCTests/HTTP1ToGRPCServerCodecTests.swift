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
import EchoImplementation
import Logging


class HTTP1ToGRPCServerCodecTests: GRPCTestCase {
  var channel: EmbeddedChannel!

  override func setUp() {
    super.setUp()
    let logger = Logger(label: "io.grpc.testing")
    let handler = HTTP1ToGRPCServerCodec<Echo_EchoRequest, Echo_EchoResponse>(logger: logger)
    self.channel = EmbeddedChannel(handler: handler)
  }

  override func tearDown() {
    super.tearDown()
    XCTAssertNoThrow(try self.channel.finish())
  }

  func makeRequestHead() -> HTTPRequestHead {
    return HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: "/echo.Echo/Get"
    )
  }

  func testDeserializationErrorOnInvalidMessageBytes() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(self.makeRequestHead())))
    var buffer = self.channel.allocator.buffer(capacity: 0)
    buffer.writeInteger(UInt8(0))  // not compressed
    buffer.writeInteger(UInt32(3)) // message is 3 bytes
    buffer.writeBytes([42, 42, 42])
    XCTAssertThrowsError(try self.channel.writeInbound(HTTPServerRequestPart.body(buffer))) { error in
      let withContext = error as? GRPCError.WithContext
      XCTAssertTrue(withContext?.error is GRPCError.DeserializationFailure)
      XCTAssertEqual(withContext?.error.makeGRPCStatus().code, .internalError)
    }
  }

  func testSingleMessageFromMultipleBodyParts() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(self.makeRequestHead())))
    let requestPart = try self.channel.readInbound(as: _GRPCServerRequestPart<Echo_EchoRequest>.self)

    switch requestPart {
    case .some(.head):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write a message across multiple buffers.
    let message = Echo_EchoRequest.with { $0.text = String(repeating: "x", count: 42) }
    let data = try message.serializedData()

    // Split the payload into two parts.
    let halfIndex = data.count / 2
    let firstChunk = data[0..<halfIndex]
    let secondChunk = data[halfIndex...]

    // Frame the message; send it in 2 parts.
    var firstBuffer = self.channel.allocator.buffer(capacity: firstChunk.count + 5)
    firstBuffer.writeInteger(UInt8(0))
    firstBuffer.writeInteger(UInt32(data.count))
    firstBuffer.writeBytes(firstChunk)
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(firstBuffer)))

    var secondBuffer = self.channel.allocator.buffer(capacity: secondChunk.count)
    secondBuffer.writeBytes(secondChunk)
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(secondBuffer)))

    let messagePart = try self.channel.readInbound(as: _GRPCServerRequestPart<Echo_EchoRequest>.self)
    switch messagePart {
    case .some(.message(let actual)):
      XCTAssertEqual(message, actual)
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }
  }

  func testMultipleMessagesFromSingleBodyPart() throws {
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.head(self.makeRequestHead())))
    let requestPart = try self.channel.readInbound(as: _GRPCServerRequestPart<Echo_EchoRequest>.self)

    switch requestPart {
    case .some(.head):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write three messages into a single body.
    var buffer = self.channel.allocator.buffer(capacity: 0)
    let messages = ["foo", "bar", "baz"].map { text in
      Echo_EchoRequest.with { $0.text = text }
    }

    for message in messages {
      let data = try message.serializedData()
      buffer.writeInteger(UInt8(0))
      buffer.writeInteger(UInt32(data.count))
      buffer.writeBytes(data)
    }

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(buffer)))

    for message in messages {
      let requestPart = try self.channel.readInbound(as: _GRPCServerRequestPart<Echo_EchoRequest>.self)
      switch requestPart {
      case .some(.message(let actual)):
        XCTAssertEqual(message, actual)
      default:
        XCTFail("Unexpected request part: \(String(describing: requestPart))")
      }
    }
  }
}
