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

  /// A scratch buffer that we encode messages into: if the buffer isn't held elsewhere then we
  /// can avoid having to allocate a new one.
  private var scratch: ByteBuffer

  init(compression: CompressionAlgorithm? = nil, allocator: ByteBufferAllocator) {
    self.compression = compression
    self.scratch = allocator.buffer(capacity: 0)

    switch self.compression?.algorithm {
    case .none, .some(.identity):
      self.compressor = nil
    case .some(.deflate):
      self.compressor = Zlib.Deflate(format: .deflate)
    case .some(.gzip):
      self.compressor = Zlib.Deflate(format: .gzip)
    }
  }

  private mutating func compress(
    buffer: ByteBuffer,
    using compressor: Zlib.Deflate
  ) throws -> ByteBuffer {
    // The compressor will allocate the correct size. For now the leading 5 bytes will do.
    self.scratch.clear(minimumCapacity: 5)
    // Set the compression byte.
    self.scratch.writeInteger(UInt8(1))
    // Set the length to zero; we'll write the actual value in a moment.
    let payloadSizeIndex = self.scratch.writerIndex
    self.scratch.writeInteger(UInt32(0))

    let bytesWritten: Int

    do {
      var buffer = buffer
      bytesWritten = try compressor.deflate(&buffer, into: &self.scratch)
    } catch {
      throw error
    }

    // Now fill in the message length.
    self.scratch.writePayloadLength(UInt32(bytesWritten), at: payloadSizeIndex)

    // Finally, the compression context should be reset between messages.
    compressor.reset()

    return self.scratch
  }

  /// Writes the readable bytes of `buffer` as a gRPC length-prefixed message.
  ///
  /// - Parameters:
  ///   - buffer: The bytes to compress and length-prefix.
  ///   - compressed: Whether the bytes should be compressed. This is ignored if not compression
  ///     mechanism was configured on this writer.
  /// - Returns: A buffer containing the length prefixed bytes.
  mutating func write(
    buffer: ByteBuffer,
    compressed: Bool = true
  ) throws -> (ByteBuffer, ByteBuffer?) {
    if compressed, let compressor = self.compressor {
      let compressedAndFramedPayload = try self.compress(buffer: buffer, using: compressor)
      return (compressedAndFramedPayload, nil)
    } else if buffer.readableBytes > Self.singleBufferSizeLimit {
      // Buffer is larger than the limit for emitting a single buffer: create a second buffer
      // containing just the message header.
      self.scratch.clear(minimumCapacity: 5)
      self.scratch.writeMultipleIntegers(UInt8(0), UInt32(buffer.readableBytes))
      return (self.scratch, buffer)
    } else {
      // We're not compressing and the message is within our single buffer size limit.
      self.scratch.clear(minimumCapacity: 5 &+ buffer.readableBytes)
      self.scratch.writeMultipleIntegers(UInt8(0), UInt32(buffer.readableBytes))
      self.scratch.writeImmutableBuffer(buffer)
      return (self.scratch, nil)
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
