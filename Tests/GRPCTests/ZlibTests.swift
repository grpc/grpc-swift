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
import NIO
import XCTest

class ZlibTests: GRPCTestCase {
  var allocator = ByteBufferAllocator()
  var inputSize = 4_096

  func makeBytes(count: Int) -> [UInt8] {
    return (0..<count).map { _ in
      UInt8.random(in: UInt8(ascii: "a")...UInt8(ascii: "z"))
    }
  }

  @discardableResult
  func doCompressAndDecompress(of bytes: [UInt8], format: Zlib.CompressionFormat) throws -> Int  {
    var data = self.allocator.buffer(capacity: 0)
    data.writeBytes(bytes)
    
    // Compress it.
    let deflate = Zlib.Deflate(format: format)
    var compressed = self.allocator.buffer(capacity: 0)
    let compressedBytesWritten = try deflate.deflate(&data, into: &compressed)
    // Did we write the right number of bytes?
    XCTAssertEqual(compressedBytesWritten, compressed.readableBytes)

    // Decompress it.
    let inflate = Zlib.Inflate(format: format)
    var decompressed = self.allocator.buffer(capacity: self.inputSize)
    let decompressedBytesWritten = try inflate.inflate(&compressed, into: &decompressed)
    // Did we write the right number of bytes?
    XCTAssertEqual(decompressedBytesWritten, decompressed.readableBytes)

    // Did we get back to where we started?
    XCTAssertEqual(decompressed.readBytes(length: decompressed.readableBytes), bytes)

    return compressedBytesWritten
  }

  func testCompressionAndDecompressionOfASCIIBytes() throws {
    let bytes = self.makeBytes(count: self.inputSize)

    for format in [Zlib.CompressionFormat.deflate, .gzip] {
      try self.doCompressAndDecompress(of: bytes, format: format)
    }
  }

  func testCompressionAndDecompressionOfZeros() throws {
    // This test makes sure the decompressor is capable of increasing the output buffer size a
    // number of times.
    let bytes: [UInt8] = Array(repeating: 0, count: self.inputSize)

    for format in [Zlib.CompressionFormat.deflate, .gzip] {
      let compressedSize = try self.doCompressAndDecompress(of: bytes, format: format)
      // Is the compressed size significantly smaller than the input size?
      XCTAssertLessThan(compressedSize, bytes.count / 4)
    }
  }

  func testCompressionAndDecompressionOfHardToCompressData() throws {
    let bytes: [UInt8] = (0..<self.inputSize).map { _ in
      return UInt8.random(in: UInt8.min...UInt8.max)
    }

    for format in [Zlib.CompressionFormat.deflate, .gzip] {
      // Is the compressed size larger than the input size?
      let compressedSize = try self.doCompressAndDecompress(of: bytes, format: format)
      print(compressedSize)
      XCTAssertGreaterThan(compressedSize, bytes.count)
    }

  }

  func testCompressionAndDecompressionWithResets() throws {
    // Generate some input.
    let byteArrays = (0..<5).map { _ in
      self.makeBytes(count: self.inputSize)
    }

    for format in [Zlib.CompressionFormat.deflate, .gzip] {
      let deflate = Zlib.Deflate(format: format)
      let inflate = Zlib.Inflate(format: format)

      for bytes in byteArrays {
        var data = self.allocator.buffer(capacity: 0)
        data.writeBytes(bytes)

        // Compress it.
        var compressed = self.allocator.buffer(capacity: 0)
        let compressedBytesWritten = try deflate.deflate(&data, into: &compressed)
        deflate.reset()

        // Did we write the right number of bytes?
        XCTAssertEqual(compressedBytesWritten, compressed.readableBytes)

        // Decompress it.
        var decompressed = self.allocator.buffer(capacity: self.inputSize)
        let decompressedBytesWritten = try inflate.inflate(&compressed, into: &decompressed)
        inflate.reset()

        // Did we write the right number of bytes?
        XCTAssertEqual(decompressedBytesWritten, decompressed.readableBytes)

        // Did we get back to where we started?
        XCTAssertEqual(decompressed.readBytes(length: decompressed.readableBytes), bytes)
      }
    }
  }

  func testDecompressThrowsOnGibberish() throws {
    let bytes = self.makeBytes(count: self.inputSize)

    for format in [Zlib.CompressionFormat.deflate, .gzip] {
      var buffer = self.allocator.buffer(capacity: bytes.count)
      buffer.writeBytes(bytes)

      let inflate = Zlib.Inflate(format: format)

      var output = self.allocator.buffer(capacity: 0)
      XCTAssertThrowsError(try inflate.inflate(&buffer, into: &output)) { error in
        let withContext = error as? GRPCError.WithContext
        XCTAssert(withContext?.error is GRPCError.ZlibCompressionFailure)
      }
    }
  }
}
