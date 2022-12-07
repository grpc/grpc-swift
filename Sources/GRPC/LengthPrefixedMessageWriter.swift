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
import Foundation
import NIOCore

internal struct LengthPrefixedMessageWriter {
  static let metadataLength = 5

  /// The compression algorithm to use, if one should be used.
  let compression: CompressionAlgorithm?
  private let compressor: Zlib.Deflate?

  /// Whether the compression message flag should be set.
  private var shouldSetCompressionFlag: Bool {
    return self.compression != nil
  }

  init(compression: CompressionAlgorithm? = nil) {
    self.compression = compression

    switch self.compression?.algorithm {
    case .none, .some(.identity):
      self.compressor = nil
    case .some(.deflate):
      self.compressor = Zlib.Deflate(format: .deflate)
    case .some(.gzip):
      self.compressor = Zlib.Deflate(format: .gzip)
    }
  }

  private func compress(
    buffer: ByteBuffer,
    using compressor: Zlib.Deflate,
    allocator: ByteBufferAllocator
  ) throws -> ByteBuffer {
    // The compressor will allocate the correct size. For now the leading 5 bytes will do.
    var output = allocator.buffer(capacity: 5)

    // Set the compression byte.
    output.writeInteger(UInt8(1))

    // Set the length to zero; we'll write the actual value in a moment.
    let payloadSizeIndex = output.writerIndex
    output.writeInteger(UInt32(0))

    let bytesWritten: Int

    do {
      var buffer = buffer
      bytesWritten = try compressor.deflate(&buffer, into: &output)
    } catch {
      throw error
    }

    // Now fill in the message length.
    output.writePayloadLength(UInt32(bytesWritten), at: payloadSizeIndex)

    // Finally, the compression context should be reset between messages.
    compressor.reset()

    return output
  }

  /// Writes the readable bytes of `buffer` as a gRPC length-prefixed message.
  ///
  /// - Parameters:
  ///   - buffer: The bytes to compress and length-prefix.
  ///   - allocator: A `ByteBufferAllocator`.
  ///   - compressed: Whether the bytes should be compressed. This is ignored if not compression
  ///     mechanism was configured on this writer.
  /// - Returns: A buffer containing the length prefixed bytes.
  func write(
    buffer: ByteBuffer,
    allocator: ByteBufferAllocator,
    compressed: Bool = true
  ) throws -> (ByteBuffer, ByteBuffer?) {
    if compressed, let compressor = self.compressor {
      let compressedAndFramedPayload = try self.compress(
        buffer: buffer,
        using: compressor,
        allocator: allocator
      )
      return (compressedAndFramedPayload, nil)
    } else if buffer.readableBytes > Self.singleBufferSizeLimit {
      // Buffer is larger than the limit for emitting a single buffer: create a second buffer
      // containing just the message header.
      var prefixed = allocator.buffer(capacity: 5)
      prefixed.writeMultipleIntegers(UInt8(0), UInt32(buffer.readableBytes))
      return (prefixed, buffer)
    } else {
      // We're not compressing and the message is within our single buffer size limit.
      var lengthPrefixed = allocator.buffer(capacity: 5 &+ buffer.readableBytes)
      // Write the compression byte and message length.
      lengthPrefixed.writeMultipleIntegers(UInt8(0), UInt32(buffer.readableBytes))
      // Write the message.
      lengthPrefixed.writeImmutableBuffer(buffer)
      return (lengthPrefixed, nil)
    }
  }

  /// Message size above which we emit two buffers: one containing the header and one with the
  /// actual message bytes. At or below the limit we copy the message into a new buffer containing
  /// both the header and the message.
  ///
  /// Using two buffers avoids expensive copies of large messages. For smaller messages the copy
  /// is cheaper than the additional allocations and overhead required to send an extra HTTP/2 DATA
  /// frame.
  ///
  /// The value of 8192 was chosen empirically. We subtract the length of the message header
  /// as `ByteBuffer` reserve capacity in powers of two and want to avoid overallocating.
  private static let singleBufferSizeLimit = 8192 - 5
}

extension ByteBuffer {
  @discardableResult
  mutating func writePayloadLength(_ length: UInt32, at index: Int) -> Int {
    let writerIndex = self.writerIndex
    defer {
      self.moveWriterIndex(to: writerIndex)
    }

    self.moveWriterIndex(to: index)
    return self.writeInteger(length)
  }
}
