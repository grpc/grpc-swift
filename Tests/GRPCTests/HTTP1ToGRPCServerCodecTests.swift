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
import EchoImplementation
import EchoModel
import Foundation
@testable import GRPC
import Logging
import NIO
import NIOHTTP1
import XCTest

/// A trivial channel handler that invokes a callback once, the first time it sees
/// channelRead.
final class OnFirstReadHandler: ChannelInboundHandler {
  typealias InboundIn = Any
  typealias InboundOut = Any

  private var callback: (() -> Void)?

  init(callback: @escaping () -> Void) {
    self.callback = callback
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    context.fireChannelRead(data)

    if let callback = self.callback {
      self.callback = nil
      callback()
    }
  }
}

final class ErrorRecordingHandler: ChannelInboundHandler {
  typealias InboundIn = Any

  var errors: [Error] = []

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.errors.append(error)
    context.fireErrorCaught(error)
  }
}

class HTTP1ToGRPCServerCodecTests: GRPCTestCase {
  var channel: EmbeddedChannel!

  override func setUp() {
    super.setUp()
    let handler = HTTP1ToGRPCServerCodec(encoding: .disabled, logger: self.logger)
    self.channel = EmbeddedChannel(handler: handler)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.finish())
    super.tearDown()
  }

  func makeRequestHead() -> HTTPRequestHead {
    return HTTPRequestHead(
      version: .init(major: 2, minor: 0),
      method: .POST,
      uri: "/echo.Echo/Get"
    )
  }

  func testSingleMessageFromMultipleBodyParts() throws {
    XCTAssertNoThrow(
      try self.channel
        .writeInbound(HTTPServerRequestPart.head(self.makeRequestHead()))
    )
    let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)

    switch requestPart {
    case .some(.headers):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write a message across multiple buffers.
    let message = Echo_EchoRequest.with { $0.text = String(repeating: "x", count: 42) }
    let data = try message.serializedData()

    // Split the payload into two parts.
    let halfIndex = data.count / 2
    let firstChunk = data[0 ..< halfIndex]
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

    let messagePart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)
    switch messagePart {
    case var .some(.message(buffer)):
      XCTAssertEqual(data, buffer.readData(length: buffer.readableBytes)!)
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }
  }

  func testMultipleMessagesFromSingleBodyPart() throws {
    XCTAssertNoThrow(
      try self.channel
        .writeInbound(HTTPServerRequestPart.head(self.makeRequestHead()))
    )
    let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)

    switch requestPart {
    case .some(.headers):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write three messages into a single body.
    var buffer = self.channel.allocator.buffer(capacity: 0)
    let serializedMessages: [Data] = try ["foo", "bar", "baz"].map { text in
      Echo_EchoRequest.with { $0.text = text }
    }.map { request in
      try request.serializedData()
    }

    for data in serializedMessages {
      buffer.writeInteger(UInt8(0))
      buffer.writeInteger(UInt32(data.count))
      buffer.writeBytes(data)
    }

    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(buffer)))

    for message in serializedMessages {
      let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)
      switch requestPart {
      case var .some(.message(buffer)):
        XCTAssertEqual(message, buffer.readData(length: buffer.readableBytes)!)
      default:
        XCTFail("Unexpected request part: \(String(describing: requestPart))")
      }
    }
  }

  func testReentrantMessageDelivery() throws {
    XCTAssertNoThrow(
      try self.channel
        .writeInbound(HTTPServerRequestPart.head(self.makeRequestHead()))
    )
    let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)

    switch requestPart {
    case .some(.headers):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write three messages into a single body.
    var buffer = self.channel.allocator.buffer(capacity: 0)
    let serializedMessages: [Data] = try ["foo", "bar", "baz"].map { text in
      Echo_EchoRequest.with { $0.text = text }
    }.map { request in
      try request.serializedData()
    }

    for data in serializedMessages {
      buffer.writeInteger(UInt8(0))
      buffer.writeInteger(UInt32(data.count))
      buffer.writeBytes(data)
    }

    // Create an OnFirstReadHandler that will _also_ send the data when it sees the first read.
    // This is try! because it cannot throw.
    let onFirstRead = OnFirstReadHandler {
      try! self.channel.writeInbound(HTTPServerRequestPart.body(buffer))
    }
    XCTAssertNoThrow(try self.channel.pipeline.addHandler(onFirstRead).wait())

    // Now write.
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(buffer)))

    // This must not re-order messages.
    for message in [serializedMessages, serializedMessages].flatMap({ $0 }) {
      let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)
      switch requestPart {
      case var .some(.message(buffer)):
        XCTAssertEqual(message, buffer.readData(length: buffer.readableBytes)!)
      default:
        XCTFail("Unexpected request part: \(String(describing: requestPart))")
      }
    }
  }

  func testErrorsOnlyHappenOnce() throws {
    XCTAssertNoThrow(
      try self.channel
        .writeInbound(HTTPServerRequestPart.head(self.makeRequestHead()))
    )
    let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)

    switch requestPart {
    case .some(.headers):
      ()
    default:
      XCTFail("Unexpected request part: \(String(describing: requestPart))")
    }

    // Write three messages into a single body.
    var buffer = self.channel.allocator.buffer(capacity: 0)
    let serializedMessages: [Data] = try ["foo", "bar", "baz"].map { text in
      Echo_EchoRequest.with { $0.text = text }
    }.map { request in
      try request.serializedData()
    }

    for data in serializedMessages {
      buffer.writeInteger(UInt8(0))
      buffer.writeInteger(UInt32(data.count))
      buffer.writeBytes(data)
    }

    // Create an OnFirstReadHandler that will _also_ send the data when it sees the first read.
    // This is try! because it cannot throw.
    let onFirstRead = OnFirstReadHandler {
      // Let's create a bad message: we'll turn on compression. We use two bytes here to deal with the fact that
      // in hitting the error we'll actually consume the first byte (whoops).
      var badBuffer = self.channel.allocator.buffer(capacity: 0)
      badBuffer.writeInteger(UInt8(1))
      badBuffer.writeInteger(UInt8(1))
      _ = try? self.channel.writeInbound(HTTPServerRequestPart.body(badBuffer))
    }
    let errorHandler = ErrorRecordingHandler()
    XCTAssertNoThrow(try self.channel.pipeline.addHandlers([onFirstRead, errorHandler]).wait())

    // Now write.
    XCTAssertNoThrow(try self.channel.writeInbound(HTTPServerRequestPart.body(buffer)))

    // We should have seen the original three messages
    for message in serializedMessages {
      let requestPart = try self.channel.readInbound(as: _RawGRPCServerRequestPart.self)
      switch requestPart {
      case var .some(.message(buffer)):
        XCTAssertEqual(message, buffer.readData(length: buffer.readableBytes)!)
      default:
        XCTFail("Unexpected request part: \(String(describing: requestPart))")
      }
    }

    // We should have recorded only one error.
    XCTAssertEqual(errorHandler.errors.count, 1)
  }
}
