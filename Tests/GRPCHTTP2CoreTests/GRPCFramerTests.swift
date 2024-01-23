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

final class GRPCFramerTests: XCTestCase {
  func testSingleWrite() throws {
    var framer = GRPCFramer()
    framer.append(Array(repeating: 42, count: 128), compress: false)

    var buffer = try XCTUnwrap(framer.next())
    let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertFalse(compressed)
    XCTAssertEqual(length, 128)
    XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 42, count: 128))
    XCTAssertEqual(buffer.readableBytes, 0)

    // No more bufers.
    XCTAssertNil(try framer.next())
  }
    
  func testSingleLargeWrite() throws {
    // A message of the maximum size it can be (accounting for the gRPC frame metadata)
    // to fit in a single GRPCFrame write buffer.
    let largeMessageSize = GRPCFramer.maximumWriteBufferLength - GRPCFramer.metadataLength
    // The size of a single-byte message, when framed in a gRPC frame (i.e. prepended with metadata).
    let singleByteGRPCFrameSize = 1 + GRPCFramer.metadataLength
    // The largest-sized message that can be coalesced in the write buffer, alongside a single-byte message.
    let smallEnoughToCoalesceSingleByteMessageSize = largeMessageSize - singleByteGRPCFrameSize
    
    var framer = GRPCFramer()
    // Apend a message that only fits in the write buffer by itself
    framer.append(Array(repeating: 42, count: largeMessageSize), compress: false)
    // Append a message that has just enough size to be coalesced with another, single-byte message (accounting for metadata).
    framer.append(Array(repeating: 43, count: smallEnoughToCoalesceSingleByteMessageSize), compress: false)
    // Append the single-byte message.
    framer.append([44], compress: false)

    var buffer = try XCTUnwrap(framer.next())
    var (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertFalse(compressed)
    XCTAssertEqual(length, UInt32(largeMessageSize))
    XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 42, count: largeMessageSize))
    XCTAssertEqual(buffer.readableBytes, 0)
    
    buffer = try XCTUnwrap(framer.next())
    (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertFalse(compressed)
    XCTAssertEqual(length, UInt32(smallEnoughToCoalesceSingleByteMessageSize))
    XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 43, count: smallEnoughToCoalesceSingleByteMessageSize))
    XCTAssertEqual(buffer.readableBytes, singleByteGRPCFrameSize)
    
    (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
    XCTAssertFalse(compressed)
    XCTAssertEqual(length, UInt32(1))
    XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(bytes: [44]))
    XCTAssertEqual(buffer.readableBytes, 0)

    // No more bufers.
    XCTAssertNil(try framer.next())
  }

  func testMultipleWrites() throws {
    var framer = GRPCFramer()

    let messages = 100
    for _ in 0 ..< messages {
      framer.append(Array(repeating: 42, count: 128), compress: false)
    }

    var buffer = try XCTUnwrap(framer.next())
    for _ in 0 ..< messages {
      let (compressed, length) = try XCTUnwrap(buffer.readMessageHeader())
      XCTAssertFalse(compressed)
      XCTAssertEqual(length, 128)
      XCTAssertEqual(buffer.readSlice(length: Int(length)), ByteBuffer(repeating: 42, count: 128))
    }

    XCTAssertEqual(buffer.readableBytes, 0)

    // No more bufers.
    XCTAssertNil(try framer.next())
  }
}

extension ByteBuffer {
  mutating func readMessageHeader() -> (Bool, UInt32)? {
    if let (compressed, length) = self.readMultipleIntegers(as: (UInt8, UInt32).self) {
      return (compressed != 0, length)
    } else {
      return nil
    }
  }
}
