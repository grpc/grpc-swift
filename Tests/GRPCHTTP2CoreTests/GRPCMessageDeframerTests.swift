/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import XCTest

@testable import GRPCHTTP2Core

final class GRPCMessageDeframerTests: XCTestCase {
  func testReadMultipleMessagesWithoutCompression() throws {
    let deframer = GRPCMessageDeframer()
    let processor = NIOSingleStepByteToMessageProcessor(deframer)

    var buffer = ByteBuffer()
    buffer.writeInteger(UInt8(0))
    buffer.writeInteger(UInt32(16))
    buffer.writeRepeatingByte(42, count: 16)

    buffer.writeInteger(UInt8(0))
    buffer.writeInteger(UInt32(8))
    buffer.writeRepeatingByte(43, count: 8)

    var messages = [[UInt8]]()
    try processor.process(buffer: buffer) { message in
      messages.append(message)
    }

    XCTAssertEqual(
      messages,
      [
        Array(repeating: 42, count: 16),
        Array(repeating: 43, count: 8),
      ]
    )
  }

  func testReadMessageOverSizeLimitWithoutCompression() throws {
    let deframer = GRPCMessageDeframer(maximumPayloadSize: 100)
    let processor = NIOSingleStepByteToMessageProcessor(deframer)

    var buffer = ByteBuffer()
    buffer.writeInteger(UInt8(0))
    buffer.writeInteger(UInt32(101))
    buffer.writeRepeatingByte(42, count: 101)

    XCTAssertThrowsRPCError(
      try processor.process(buffer: buffer) { _ in
        XCTFail("No message should be produced.")
      }
    ) { error in
      XCTAssertEqual(error.code, .resourceExhausted)
      XCTAssertEqual(
        error.message,
        "Message has exceeded the configured maximum payload size (max: 100, actual: 101)"
      )
    }
  }

  func testReadSingleMessageWithoutCompressionSplitAcrossMultipleBuffers() throws {
    let deframer = GRPCMessageDeframer()
    let processor = NIOSingleStepByteToMessageProcessor(deframer)

    var buffer = ByteBuffer()

    // We want to write the following gRPC frame:
    // - Compression flag unset
    // - Message length = 120
    // - 120 bytes of data for the message
    // The header will be split in two (the first 3 bytes in a buffer, the
    // remaining 2 in another one); the first chunk of the message will follow
    // the second part of the metadata in the second buffer; and finally
    // the rest of the message bytes in a third buffer.
    // The purpose of this test is to make sure that we are correctly stitching
    // together the frame.

    // Write compression flag (unset)
    buffer.writeInteger(UInt8(0))
    // Write the first two bytes of the length field
    buffer.writeInteger(UInt16(0))
    // Make sure we don't produce a message, since we've got incomplete data.
    try processor.process(buffer: buffer) { message in
      XCTAssertNil(message)
    }

    buffer.clear()
    // Write the next two bytes of the length field
    buffer.writeInteger(UInt16(120))
    // Write the first half of the message data
    buffer.writeRepeatingByte(42, count: 60)
    // Again, make sure we don't produce a message, since we don't have enough
    // message bytes to read (only have 60 so far, but need 120).
    try processor.process(buffer: buffer) { message in
      XCTAssertNil(message)
    }

    buffer.clear()
    // Write remaining 60 bytes of the message.
    buffer.writeRepeatingByte(43, count: 60)

    // Now we should be reading the full message.
    var messages = [[UInt8]]()
    try processor.process(buffer: buffer) { message in
      messages.append(message)
    }
    let expectedMessage = {
      var firstHalf = Array(repeating: UInt8(42), count: 60)
      firstHalf.append(contentsOf: Array(repeating: 43, count: 60))
      return firstHalf
    }()
    XCTAssertEqual(messages, [expectedMessage])
  }

  func testReadMultipleMessagesWithCompression() throws {
    let decompressor = Zlib.Decompressor(method: .deflate)
    let deframer = GRPCMessageDeframer(maximumPayloadSize: 1000, decompressor: decompressor)
    let processor = NIOSingleStepByteToMessageProcessor(deframer)
    let compressor = Zlib.Compressor(method: .deflate)
    var framer = GRPCMessageFramer()

    framer.append(Array(repeating: 42, count: 100))
    var framedMessage = try framer.next(compressor: compressor)!

    var messages = [[UInt8]]()
    try processor.process(buffer: framedMessage) { message in
      messages.append(message)
    }

    framer.append(Array(repeating: 43, count: 110))
    framedMessage = try framer.next(compressor: compressor)!
    try processor.process(buffer: framedMessage) { message in
      messages.append(message)
    }

    XCTAssertEqual(
      messages,
      [
        Array(repeating: 42, count: 100),
        Array(repeating: 43, count: 110),
      ]
    )
  }

  func testReadMessageOverSizeLimitWithCompression() throws {
    let decompressor = Zlib.Decompressor(method: .deflate)
    let deframer = GRPCMessageDeframer(maximumPayloadSize: 100, decompressor: decompressor)
    let processor = NIOSingleStepByteToMessageProcessor(deframer)

    let compressor = Zlib.Compressor(method: .deflate)
    var framer = GRPCMessageFramer()
    framer.append(Array(repeating: 42, count: 101))
    var framedMessage = try framer.next(compressor: compressor)!

    XCTAssertThrowsRPCError(
      try processor.process(buffer: framedMessage) { _ in
        XCTFail("No message should be produced.")
      }
    ) { error in
      XCTAssertEqual(error.code, .resourceExhausted)
      XCTAssertEqual(error.message, "Message is too large to decompress.")
    }
  }

  func testReadSingleMessageWithCompressionSplitAcrossMultipleBuffers() throws {
    let decompressor = Zlib.Decompressor(method: .deflate)
    let deframer = GRPCMessageDeframer(maximumPayloadSize: 100, decompressor: decompressor)
    let processor = NIOSingleStepByteToMessageProcessor(deframer)
    let compressor = Zlib.Compressor(method: .deflate)
    var framer = GRPCMessageFramer()

    framer.append(Array(repeating: 42, count: 100))
    var framedMessage = try framer.next(compressor: compressor)!
    var firstBuffer = ByteBuffer(buffer: framedMessage.readSlice(length: 3)!)
    var secondBuffer = ByteBuffer(buffer: framedMessage.readSlice(length: 3)!)
    var thirdBuffer = ByteBuffer(buffer: framedMessage)
    framedMessage.moveReaderIndex(to: 0)

    // Make sure we don't produce a message, since we've got incomplete data.
    try processor.process(buffer: firstBuffer) { message in
      XCTFail("No message should be produced.")
    }

    // Again, make sure we don't produce a message, since we don't have enough
    // message bytes to read.
    try processor.process(buffer: secondBuffer) { message in
      XCTFail("No message should be produced.")
    }

    // Now we should be reading the full message.
    var messages = [[UInt8]]()
    try processor.process(buffer: thirdBuffer) { message in
      messages.append(message)
    }
    // Assert the retrieved message matches the uncompressed original message.
    XCTAssertEqual(messages, [Array(repeating: 42, count: 100)])
  }
}
