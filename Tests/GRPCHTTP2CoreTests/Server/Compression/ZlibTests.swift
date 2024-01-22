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

import GRPCCore
import NIOCore
import XCTest

@testable import GRPCHTTP2Core

final class ZlibTests: XCTestCase {
  private let text = """
    Here's to the crazy ones. The misfits. The rebels. The troublemakers. The round pegs in the
    square holes. The ones who see things differently. They're not fond of rules. And they have
    no respect for the status quo. You can quote them, disagree with them, glorify or vilify them.
    About the only thing you can't do is ignore them. Because they change things. They push the
    human race forward. And while some may see them as the crazy ones, we see genius. Because
    the people who are crazy enough to think they can change the world, are the ones who do.
    """

  private func compress(_ input: [UInt8], method: Zlib.Method) throws -> ByteBuffer {
    var compressor = Zlib.Compressor(method: method)
    compressor.initialize()
    defer { compressor.end() }

    var buffer = ByteBuffer()
    try compressor.compress(input, into: &buffer)
    return buffer
  }

  private func decompress(
    _ input: ByteBuffer,
    method: Zlib.Method,
    limit: Int = .max
  ) throws -> [UInt8] {
    var decompressor = Zlib.Decompressor(method: method)
    decompressor.initialize()
    defer { decompressor.end() }

    var input = input
    return try decompressor.decompress(&input, limit: limit)
  }

  func testRoundTripUsingDeflate() throws {
    let original = Array(self.text.utf8)
    let compressed = try self.compress(original, method: .deflate)
    let decompressed = try self.decompress(compressed, method: .deflate)
    XCTAssertEqual(original, decompressed)
  }

  func testRoundTripUsingGzip() throws {
    let original = Array(self.text.utf8)
    let compressed = try self.compress(original, method: .gzip)
    let decompressed = try self.decompress(compressed, method: .gzip)
    XCTAssertEqual(original, decompressed)
  }

  func testRepeatedCompresses() throws {
    let original = Array(self.text.utf8)
    var compressor = Zlib.Compressor(method: .deflate)
    compressor.initialize()
    defer { compressor.end() }

    var compressed = ByteBuffer()
    let bytesWritten = try compressor.compress(original, into: &compressed)
    XCTAssertEqual(compressed.readableBytes, bytesWritten)

    for _ in 0 ..< 10 {
      var buffer = ByteBuffer()
      try compressor.compress(original, into: &buffer)
      XCTAssertEqual(compressed, buffer)
    }
  }

  func testRepeatedDecompresses() throws {
    let original = Array(self.text.utf8)
    var decompressor = Zlib.Decompressor(method: .deflate)
    decompressor.initialize()
    defer { decompressor.end() }

    let compressed = try self.compress(original, method: .deflate)
    var input = compressed
    let decompressed = try decompressor.decompress(&input, limit: .max)

    for _ in 0 ..< 10 {
      var input = compressed
      let buffer = try decompressor.decompress(&input, limit: .max)
      XCTAssertEqual(buffer, decompressed)
    }
  }

  func testDecompressGrowsOutputBuffer() throws {
    // This compresses down to 17 bytes with deflate. The decompressor sets the output buffer to
    // be double the size of the input buffer and will grow it if necessary. This test exercises
    // that path.
    let original = [UInt8](repeating: 0, count: 1024)
    let compressed = try self.compress(original, method: .deflate)
    let decompressed = try self.decompress(compressed, method: .deflate)
    XCTAssertEqual(decompressed, original)
  }

  func testDecompressRespectsLimit() throws {
    let compressed = try self.compress(Array(self.text.utf8), method: .deflate)
    let limit = compressed.readableBytes - 1
    XCTAssertThrowsError(
      ofType: RPCError.self,
      try self.decompress(compressed, method: .deflate, limit: limit)
    ) { error in
      XCTAssertEqual(error.code, .resourceExhausted)
    }
  }

  func testCompressAppendsToBuffer() throws {
    var compressor = Zlib.Compressor(method: .deflate)
    compressor.initialize()
    defer { compressor.end() }

    var buffer = ByteBuffer()
    try compressor.compress(Array(repeating: 0, count: 1024), into: &buffer)

    // Should be some readable bytes.
    let byteCount1 = buffer.readableBytes
    XCTAssertGreaterThan(byteCount1, 0)

    try compressor.compress(Array(repeating: 1, count: 1024), into: &buffer)

    // Should be some readable bytes.
    let byteCount2 = buffer.readableBytes
    XCTAssertGreaterThan(byteCount2, byteCount1)

    let slice1 = buffer.readSlice(length: byteCount1)!
    let decompressed1 = try self.decompress(slice1, method: .deflate)
    XCTAssertEqual(decompressed1, Array(repeating: 0, count: 1024))

    let decompressed2 = try self.decompress(buffer, method: .deflate)
    XCTAssertEqual(decompressed2, Array(repeating: 1, count: 1024))
  }
}
