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
@testable import GRPC
import Logging
import NIO
import XCTest

class LengthPrefixedMessageReaderTests: GRPCTestCase {
  var reader: LengthPrefixedMessageReader!

  override func setUp() {
    super.setUp()
    self.reader = LengthPrefixedMessageReader()
  }

  var allocator = ByteBufferAllocator()

  func byteBuffer(withBytes bytes: [UInt8]) -> ByteBuffer {
    var buffer = self.allocator.buffer(capacity: bytes.count)
    buffer.writeBytes(bytes)
    return buffer
  }

  final let twoByteMessage: [UInt8] = [0x01, 0x02]
  func lengthPrefixedTwoByteMessage(withCompression compression: Bool = false) -> [UInt8] {
    return [
      compression ? 0x01 : 0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02, // 4-byte message length (2)
    ] + self.twoByteMessage
  }

  private func assertMessagesEqual(
    expected expectedBytes: [UInt8],
    actual buffer: ByteBuffer?,
    line: UInt = #line
  ) {
    guard let buffer = buffer else {
      XCTFail("buffer is nil", line: line)
      return
    }

    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: expectedBytes.count) else {
      XCTFail(
        "Expected \(expectedBytes.count) bytes, but only \(buffer.readableBytes) bytes are readable",
        line: line
      )
      return
    }

    XCTAssertEqual(expectedBytes, bytes, line: line)
  }

  func testNextMessageReturnsNilWhenNoBytesAppended() throws {
    XCTAssertNil(try self.reader.nextMessage())
  }

  func testNextMessageReturnsMessageIsAppendedInOneBuffer() throws {
    var buffer = self.byteBuffer(withBytes: self.lengthPrefixedTwoByteMessage())
    self.reader.append(buffer: &buffer)

    self.assertMessagesEqual(expected: self.twoByteMessage, actual: try self.reader.nextMessage())
  }

  func testNextMessageReturnsMessageForZeroLengthMessage() throws {
    let bytes: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x00, // 4-byte message length (0)
      // 0-byte message
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    self.assertMessagesEqual(expected: [], actual: try self.reader.nextMessage())
  }

  func testNextMessageDeliveredAcrossMultipleByteBuffers() throws {
    let firstBytes: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, // first 3 bytes of 4-byte message length
    ]

    let secondBytes: [UInt8] = [
      0x02, // fourth byte of 4-byte message length (2)
      0xF0, 0xBA, // 2-byte message
    ]

    var firstBuffer = self.byteBuffer(withBytes: firstBytes)
    self.reader.append(buffer: &firstBuffer)
    var secondBuffer = self.byteBuffer(withBytes: secondBytes)
    self.reader.append(buffer: &secondBuffer)

    self.assertMessagesEqual(expected: [0xF0, 0xBA], actual: try self.reader.nextMessage())
  }

  func testNextMessageWhenMultipleMessagesAreBuffered() throws {
    let bytes: [UInt8] = [
      // 1st message
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02, // 4-byte message length (2)
      0x0F, 0x00, // 2-byte message
      // 2nd message
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x04, // 4-byte message length (4)
      0xDE, 0xAD, 0xBE, 0xEF, // 4-byte message
      // 3rd message
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x01, // 4-byte message length (1)
      0x01, // 1-byte message
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    self.assertMessagesEqual(expected: [0x0F, 0x00], actual: try self.reader.nextMessage())
    self.assertMessagesEqual(
      expected: [0xDE, 0xAD, 0xBE, 0xEF],
      actual: try self.reader.nextMessage()
    )
    self.assertMessagesEqual(expected: [0x01], actual: try self.reader.nextMessage())
  }

  func testNextMessageReturnsNilWhenNoMessageLengthIsAvailable() throws {
    let bytes: [UInt8] = [
      0x00, // 1-byte compression flag
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    XCTAssertNil(try self.reader.nextMessage())

    // Ensure we can read a message when the rest of the bytes are delivered
    let restOfBytes: [UInt8] = [
      0x00, 0x00, 0x00, 0x01, // 4-byte message length (1)
      0x00, // 1-byte message
    ]

    var secondBuffer = self.byteBuffer(withBytes: restOfBytes)
    self.reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(expected: [0x00], actual: try self.reader.nextMessage())
  }

  func testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable() throws {
    let bytes: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, // 2-bytes of message length (should be 4)
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    XCTAssertNil(try self.reader.nextMessage())

    // Ensure we can read a message when the rest of the bytes are delivered
    let restOfBytes: [UInt8] = [
      0x00, 0x01, // 4-byte message length (1)
      0x00, // 1-byte message
    ]

    var secondBuffer = self.byteBuffer(withBytes: restOfBytes)
    self.reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(expected: [0x00], actual: try self.reader.nextMessage())
  }

  func testNextMessageReturnsNilWhenNoMessageBytesAreAvailable() throws {
    let bytes: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02, // 4-byte message length (2)
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    XCTAssertNil(try self.reader.nextMessage())

    // Ensure we can read a message when the rest of the bytes are delivered
    var secondBuffer = self.byteBuffer(withBytes: self.twoByteMessage)
    self.reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(expected: self.twoByteMessage, actual: try self.reader.nextMessage())
  }

  func testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable() throws {
    let bytes: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02, // 4-byte message length (2)
      0x00, // 1-byte of message
    ]

    var buffer = self.byteBuffer(withBytes: bytes)
    self.reader.append(buffer: &buffer)

    XCTAssertNil(try self.reader.nextMessage())

    // Ensure we can read a message when the rest of the bytes are delivered
    let restOfBytes: [UInt8] = [
      0x01, // final byte of message
    ]

    var secondBuffer = self.byteBuffer(withBytes: restOfBytes)
    self.reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(expected: [0x00, 0x01], actual: try self.reader.nextMessage())
  }

  func testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected() throws {
    // Default compression mechanism is `nil` which requires that no
    // compression flag is set as it indicates a lack of message encoding header.
    XCTAssertNil(self.reader.compression)

    var buffer = self
      .byteBuffer(withBytes: self.lengthPrefixedTwoByteMessage(withCompression: true))
    self.reader.append(buffer: &buffer)

    XCTAssertThrowsError(try self.reader.nextMessage()) { error in
      let errorWithContext = error as? GRPCError.WithContext
      XCTAssertTrue(errorWithContext?.error is GRPCError.CompressionUnsupported)
    }
  }

  func testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet() throws {
    // `.identity` should always be supported and requires a flag.
    self.reader = LengthPrefixedMessageReader(compression: .identity, decompressionLimit: .ratio(1))

    var buffer = self.byteBuffer(withBytes: self.lengthPrefixedTwoByteMessage())
    self.reader.append(buffer: &buffer)

    self.assertMessagesEqual(expected: self.twoByteMessage, actual: try self.reader.nextMessage())
  }

  func testAppendReadsAllBytes() throws {
    var buffer = self.byteBuffer(withBytes: self.lengthPrefixedTwoByteMessage())
    self.reader.append(buffer: &buffer)

    XCTAssertEqual(0, buffer.readableBytes)
  }

  func testExcessiveBytesAreDiscarded() throws {
    // We're going to use a 1kB message here for ease of testing.
    let message = Array(repeating: UInt8(0), count: 1024)
    let largeMessage: [UInt8] = [
      0x00, // 1-byte compression flag
      0x00, 0x00, 0x04, 0x00, // 4-byte message length (1024)
    ] + message
    var buffer = self.byteBuffer(withBytes: largeMessage)
    buffer.writeBytes(largeMessage)
    buffer.writeBytes(largeMessage)
    self.reader.append(buffer: &buffer)

    XCTAssertEqual(self.reader.unprocessedBytes, (1024 + 5) * 3)
    XCTAssertEqual(self.reader._consumedNonDiscardedBytes, 0)

    self.assertMessagesEqual(expected: message, actual: try self.reader.nextMessage())
    XCTAssertEqual(self.reader.unprocessedBytes, (1024 + 5) * 2)
    XCTAssertEqual(self.reader._consumedNonDiscardedBytes, 1024 + 5)

    self.assertMessagesEqual(expected: message, actual: try self.reader.nextMessage())
    XCTAssertEqual(self.reader.unprocessedBytes, 1024 + 5)
    XCTAssertEqual(self.reader._consumedNonDiscardedBytes, 0)
  }
}

extension LengthPrefixedMessageReader {
  fileprivate mutating func nextMessage() throws -> ByteBuffer? {
    return try self.nextMessage(maxLength: .max)
  }
}
