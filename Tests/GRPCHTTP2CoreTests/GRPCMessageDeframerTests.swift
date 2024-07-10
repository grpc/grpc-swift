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

import GRPCHTTP2Core
import NIOCore
import XCTest

final class GRPCMessageDeframerTests: XCTestCase {
  // Most of the functionality is tested by the 'GRPCMessageDecoder' tests.

  func testDecodeNoBytes() {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)
    XCTAssertNil(try deframer.decodeNext())
  }

  func testDecodeNotEnoughBytes() {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)
    let bytes: [UInt8] = [
      0x0,  // Compression byte (not compressed)
      0x0, 0x0, 0x0, 0x1,  // Length (1)
    ]
    deframer.append(ByteBuffer(bytes: bytes))
    XCTAssertNil(try deframer.decodeNext())
  }

  func testDecodeZeroLengthMessage() {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)
    let bytes: [UInt8] = [
      0x0,  // Compression byte (not compressed)
      0x0, 0x0, 0x0, 0x0,  // Length (0)
    ]
    deframer.append(ByteBuffer(bytes: bytes))
    XCTAssertEqual(try deframer.decodeNext(), [])
  }

  func testDecodeMessage() {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)
    let bytes: [UInt8] = [
      0x0,  // Compression byte (not compressed)
      0x0, 0x0, 0x0, 0x1,  // Length (1)
      0xf,  // Payload
    ]
    deframer.append(ByteBuffer(bytes: bytes))
    XCTAssertEqual(try deframer.decodeNext(), [0xf])
  }

  func testDripFeedAndDecode() {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)
    let bytes: [UInt8] = [
      0x0,  // Compression byte (not compressed)
      0x0, 0x0, 0x0, 0x1,  // Length (1)
    ]

    for byte in bytes {
      deframer.append(ByteBuffer(bytes: [byte]))
      XCTAssertNil(try deframer.decodeNext())
    }

    // Drip feed the last byte.
    deframer.append(ByteBuffer(bytes: [0xf]))
    XCTAssertEqual(try deframer.decodeNext(), [0xf])
  }

  func testReadBytesAreDiscarded() throws {
    var deframer = GRPCMessageDeframer(maxPayloadSize: .max)

    var input = ByteBuffer()
    input.writeInteger(UInt8(0))  // Compression byte (not compressed)
    input.writeInteger(UInt32(1024))  // Length
    input.writeRepeatingByte(42, count: 1024)  // Payload

    input.writeInteger(UInt8(0))  // Compression byte (not compressed)
    input.writeInteger(UInt32(1024))  // Length
    input.writeRepeatingByte(43, count: 512)  // Payload (most of it)

    deframer.append(input)
    XCTAssertEqual(deframer._readerIndex, 0)

    let message1 = try deframer.decodeNext()
    XCTAssertEqual(message1, Array(repeating: 42, count: 1024))
    XCTAssertNotEqual(deframer._readerIndex, 0)

    // Append the final byte. This should discard any read bytes and set the reader index back
    // to zero.
    deframer.append(ByteBuffer(repeating: 43, count: 512))
    XCTAssertEqual(deframer._readerIndex, 0)

    // Read the message
    let message2 = try deframer.decodeNext()
    XCTAssertEqual(message2, Array(repeating: 43, count: 1024))
    XCTAssertNotEqual(deframer._readerIndex, 0)
  }
}
