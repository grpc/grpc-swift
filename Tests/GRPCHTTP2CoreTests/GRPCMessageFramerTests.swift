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

final class GRPCMessageFramerTests: XCTestCase {
  func testSingleWrite() throws {
    var framer = GRPCMessageFramer()
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

  func testMultipleWrites() throws {
    var framer = GRPCMessageFramer()

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
