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
@testable import GRPC
import NIOCore
import XCTest

class LengthPrefixedMessageWriterTests: GRPCTestCase {
  func testWriteBytesWithNoLeadingSpaceOrCompression() throws {
    var writer = LengthPrefixedMessageWriter()
    let allocator = ByteBufferAllocator()
    let buffer = allocator.buffer(bytes: [1, 2, 3])

    var (prefixed, other) = try writer.write(buffer: buffer)
    XCTAssertNil(other)
    XCTAssertEqual(prefixed.readInteger(as: UInt8.self), 0)
    XCTAssertEqual(prefixed.readInteger(as: UInt32.self), 3)
    XCTAssertEqual(prefixed.readBytes(length: 3), [1, 2, 3])
    XCTAssertEqual(prefixed.readableBytes, 0)
  }

  func testWriteBytesWithLeadingSpaceAndNoCompression() throws {
    var writer = LengthPrefixedMessageWriter()
    let allocator = ByteBufferAllocator()

    var buffer = allocator.buffer(bytes: Array(repeating: 0, count: 5) + [1, 2, 3])
    buffer.moveReaderIndex(forwardBy: 5)

    var (prefixed, other) = try writer.write(buffer: buffer)
    XCTAssertNil(other)
    XCTAssertEqual(prefixed.readInteger(as: UInt8.self), 0)
    XCTAssertEqual(prefixed.readInteger(as: UInt32.self), 3)
    XCTAssertEqual(prefixed.readBytes(length: 3), [1, 2, 3])
    XCTAssertEqual(prefixed.readableBytes, 0)
  }

  func testWriteBytesWithNoLeadingSpaceAndCompression() throws {
    var writer = LengthPrefixedMessageWriter(compression: .gzip)
    let allocator = ByteBufferAllocator()

    let buffer = allocator.buffer(bytes: [1, 2, 3])
    var (prefixed, other) = try writer.write(buffer: buffer)
    XCTAssertNil(other)

    XCTAssertEqual(prefixed.readInteger(as: UInt8.self), 1)
    let size = prefixed.readInteger(as: UInt32.self)!
    XCTAssertGreaterThanOrEqual(size, 0)
    XCTAssertNotNil(prefixed.readBytes(length: Int(size)))
    XCTAssertEqual(prefixed.readableBytes, 0)
  }

  func testWriteBytesWithLeadingSpaceAndCompression() throws {
    var writer = LengthPrefixedMessageWriter(compression: .gzip)
    let allocator = ByteBufferAllocator()

    var buffer = allocator.buffer(bytes: Array(repeating: 0, count: 5) + [1, 2, 3])
    buffer.moveReaderIndex(forwardBy: 5)
    var (prefixed, other) = try writer.write(buffer: buffer)
    XCTAssertNil(other)

    XCTAssertEqual(prefixed.readInteger(as: UInt8.self), 1)
    let size = prefixed.readInteger(as: UInt32.self)!
    XCTAssertGreaterThanOrEqual(size, 0)
    XCTAssertNotNil(prefixed.readBytes(length: Int(size)))
    XCTAssertEqual(prefixed.readableBytes, 0)
  }

  func testLargeCompressedPayloadEmitsOneBuffer() throws {
    var writer = LengthPrefixedMessageWriter(compression: .gzip)
    let allocator = ByteBufferAllocator()
    let message = ByteBuffer(repeating: 0, count: 16 * 1024 * 1024)

    var (lengthPrefixed, other) = try writer.write(buffer: message)
    XCTAssertNil(other)
    XCTAssertEqual(lengthPrefixed.readInteger(as: UInt8.self), 1)
    let length = lengthPrefixed.readInteger(as: UInt32.self)
    XCTAssertEqual(length, UInt32(lengthPrefixed.readableBytes))
  }

  func testLargeUncompressedPayloadEmitsTwoBuffers() throws {
    var writer = LengthPrefixedMessageWriter(compression: .none)
    let allocator = ByteBufferAllocator()
    let message = ByteBuffer(repeating: 0, count: 16 * 1024 * 1024)

    var (header, payload) = try writer.write(buffer: message)
    XCTAssertEqual(header.readInteger(as: UInt8.self), 0)
    XCTAssertEqual(header.readInteger(as: UInt32.self), UInt32(message.readableBytes))
    XCTAssertEqual(header.readableBytes, 0)
    XCTAssertEqual(payload, message)
  }
}

extension LengthPrefixedMessageWriter {
  init(compression: CompressionAlgorithm? = nil) {
    self.init(compression: compression, allocator: .init())
  }
}
