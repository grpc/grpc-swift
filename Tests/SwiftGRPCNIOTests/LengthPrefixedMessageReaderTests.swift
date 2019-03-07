import Foundation
import XCTest
import SwiftGRPCNIO
import NIO

class LengthPrefixedMessageReaderTests: XCTestCase {
  static var allTests: [(String, (LengthPrefixedMessageReaderTests) -> () throws -> Void)] {
    return [
      ("testNextMessageReturnsNilWhenNoBytesAppended", testNextMessageReturnsNilWhenNoBytesAppended),
      ("testNextMessageReturnsMessageIsAppendedInOneBuffer", testNextMessageReturnsMessageIsAppendedInOneBuffer),
      ("testNextMessageReturnsMessageForZeroLengthMessage", testNextMessageReturnsMessageForZeroLengthMessage),
      ("testNextMessageDeliveredAcrossMultipleByteBuffers", testNextMessageDeliveredAcrossMultipleByteBuffers),
      ("testNextMessageWhenMultipleMessagesAreBuffered", testNextMessageWhenMultipleMessagesAreBuffered),
      ("testNextMessageReturnsNilWhenNoMessageLengthIsAvailable", testNextMessageReturnsNilWhenNoMessageLengthIsAvailable),
      ("testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable", testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable),
      ("testNextMessageReturnsNilWhenNoMessageBytesAreAvailable", testNextMessageReturnsNilWhenNoMessageBytesAreAvailable),
      ("testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable", testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable),
      ("testNextMessageThrowsWhenCompressionMechanismIsNotSupported", testNextMessageThrowsWhenCompressionMechanismIsNotSupported),
      ("testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected", testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected),
      ("testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet", testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet),
      ("testAppendReadsAllBytes", testAppendReadsAllBytes),
    ]
  }

  var reader = LengthPrefixedMessageReader(mode: .client, compressionMechanism: .none)

  var allocator = ByteBufferAllocator()

  func byteBuffer(withBytes bytes: [UInt8]) -> ByteBuffer {
    var buffer = allocator.buffer(capacity: bytes.count)
    buffer.write(bytes: bytes)
    return buffer
  }

  final let twoByteMessage: [UInt8] = [0x01, 0x02]
  func lengthPrefixedTwoByteMessage(withCompression compression: Bool = false) -> [UInt8] {
    return [
      compression ? 0x01 : 0x00,  // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02,     // 4-byte message length (2)
    ] + twoByteMessage
  }

  func assertMessagesEqual(_ buffer: ByteBuffer?, expected expectedBytes: [UInt8], file: StaticString = #file, line: UInt = #line) {
    guard let buffer = buffer else {
      XCTFail("buffer is nil", file: file, line: line)
      return
    }

    guard let bytes = buffer.getBytes(at: buffer.readerIndex, length: expectedBytes.count) else {
      XCTFail("Expected \(expectedBytes.count) bytes, but only \(buffer.readableBytes) bytes are readable", file: file, line: line)
      return
    }

    XCTAssertEqual(bytes, expectedBytes, file: file, line: line)
  }

  func testNextMessageReturnsNilWhenNoBytesAppended() throws {
    XCTAssertNil(try reader.nextMessage())
  }

  func testNextMessageReturnsMessageIsAppendedInOneBuffer() throws {
    var buffer = byteBuffer(withBytes: lengthPrefixedTwoByteMessage())
    reader.append(buffer: &buffer)

    self.assertMessagesEqual(try reader.nextMessage(), expected: twoByteMessage)
  }

  func testNextMessageReturnsMessageForZeroLengthMessage() throws {
    let bytes: [UInt8] = [
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x00,  // 4-byte message length (0)
                               // 0-byte message
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    self.assertMessagesEqual(try reader.nextMessage(), expected: [])
  }

  func testNextMessageDeliveredAcrossMultipleByteBuffers() throws {
    let firstBytes: [UInt8] = [
      0x00,              // 1-byte compression flag
      0x00, 0x00, 0x00,  // first 3 bytes of 4-byte message length
    ]

    let secondBytes: [UInt8] = [
      0x02,              // fourth byte of 4-byte message length (2)
      0xf0, 0xba,        // 2-byte message
    ]

    var firstBuffer = byteBuffer(withBytes: firstBytes)
    reader.append(buffer: &firstBuffer)
    var secondBuffer = byteBuffer(withBytes: secondBytes)
    reader.append(buffer: &secondBuffer)

    self.assertMessagesEqual(try reader.nextMessage(), expected: [0xf0, 0xba])
  }

  func testNextMessageWhenMultipleMessagesAreBuffered() throws {
    let bytes: [UInt8] = [
      // 1st message
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02,  // 4-byte message length (2)
      0x0f, 0x00,              // 2-byte message
      // 2nd message
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x04,  // 4-byte message length (4)
      0xde, 0xad, 0xbe, 0xef,  // 4-byte message
      // 3rd message
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x01,  // 4-byte message length (1)
      0x01,                    // 1-byte message
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    self.assertMessagesEqual(try reader.nextMessage(), expected: [0x0f, 0x00])
    self.assertMessagesEqual(try reader.nextMessage(), expected: [0xde, 0xad, 0xbe, 0xef])
    self.assertMessagesEqual(try reader.nextMessage(), expected: [0x01])
  }

  func testNextMessageReturnsNilWhenNoMessageLengthIsAvailable() throws {
    let bytes: [UInt8] = [
      0x00,  // 1-byte compression flag
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    XCTAssertNil(try reader.nextMessage())

    let restOfBytes: [UInt8] = [
      0x00, 0x00, 0x00, 0x01,  // 4-byte message length (1)
      0x00,                    // 1-byte message
    ]

    var secondBuffer = byteBuffer(withBytes: restOfBytes)
    reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(try reader.nextMessage(), expected: [0x00])
  }

  func testNextMessageReturnsNilWhenNotAllMessageLengthIsAvailable() throws {
    let bytes: [UInt8] = [
      0x00,        // 1-byte compression flag
      0x00, 0x00,  // 2-bytes of message length (should be 4)
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    XCTAssertNil(try reader.nextMessage())

    let restOfBytes: [UInt8] = [
      0x00, 0x01,  // 4-byte message length (1)
      0x00,        // 1-byte message
    ]

    var secondBuffer = byteBuffer(withBytes: restOfBytes)
    reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(try reader.nextMessage(), expected: [0x00])
  }


  func testNextMessageReturnsNilWhenNoMessageBytesAreAvailable() throws {
    let bytes: [UInt8] = [
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02,  // 4-byte message length (2)
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    XCTAssertNil(try reader.nextMessage())

    var secondBuffer = byteBuffer(withBytes: twoByteMessage)
    reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(try reader.nextMessage(), expected: twoByteMessage)
  }

  func testNextMessageReturnsNilWhenNotAllMessageBytesAreAvailable() throws {
    let bytes: [UInt8] = [
      0x00,                    // 1-byte compression flag
      0x00, 0x00, 0x00, 0x02,  // 4-byte message length (2)
      0x00,                    // 1-byte of message
    ]

    var buffer = byteBuffer(withBytes: bytes)
    reader.append(buffer: &buffer)

    XCTAssertNil(try reader.nextMessage())

    let restOfBytes: [UInt8] = [
      0x01  // final byte of message
    ]

    var secondBuffer = byteBuffer(withBytes: restOfBytes)
    reader.append(buffer: &secondBuffer)
    self.assertMessagesEqual(try reader.nextMessage(), expected: [0x00, 0x01])
  }

  func testNextMessageThrowsWhenCompressionMechanismIsNotSupported() throws {
    // Unknown should never be supported.
    reader.compressionMechanism = .unknown
    XCTAssertFalse(reader.compressionMechanism.supported)

    var buffer = byteBuffer(withBytes: lengthPrefixedTwoByteMessage(withCompression: true))
    reader.append(buffer: &buffer)

    XCTAssertThrowsError(try reader.nextMessage()) { error in
      XCTAssertEqual((error as? GRPCError)?.error as? GRPCCommonError, .unsupportedCompressionMechanism("unknown"))
    }
  }

  func testNextMessageThrowsWhenCompressionFlagIsSetButNotExpected() throws {
    // Default compression mechanism is `.none` which requires that no
    // compression flag is set as it indicates a lack of message encoding header.
    XCTAssertFalse(reader.compressionMechanism.requiresFlag)

    var buffer = byteBuffer(withBytes: lengthPrefixedTwoByteMessage(withCompression: true))
    reader.append(buffer: &buffer)

    XCTAssertThrowsError(try reader.nextMessage()) { error in
      XCTAssertEqual((error as? GRPCError)?.error as? GRPCCommonError, .unexpectedCompression)
    }
  }

  func testNextMessageDoesNotThrowWhenCompressionFlagIsExpectedButNotSet() throws {
    // `.identity` should always be supported and requires a flag.
    reader.compressionMechanism = .identity
    XCTAssertTrue(reader.compressionMechanism.supported)
    XCTAssertTrue(reader.compressionMechanism.requiresFlag)

    var buffer = byteBuffer(withBytes: lengthPrefixedTwoByteMessage())
    reader.append(buffer: &buffer)

    self.assertMessagesEqual(try reader.nextMessage(), expected: twoByteMessage)
  }

  func testAppendReadsAllBytes() throws {
    var buffer = byteBuffer(withBytes: lengthPrefixedTwoByteMessage())
    reader.append(buffer: &buffer)

    XCTAssertEqual(buffer.readableBytes, 0)
  }
}
