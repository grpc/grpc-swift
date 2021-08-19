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
  func write(buffer: ByteBuffer, allocator: ByteBufferAllocator,
             compressed: Bool = true) throws -> ByteBuffer {
    if compressed, let compressor = self.compressor {
      return try self.compress(buffer: buffer, using: compressor, allocator: allocator)
    } else if buffer.readerIndex >= 5 {
      // We're not compressing and we have enough bytes before the reader index that we can write
      // over with the compression byte and length.
      var buffer = buffer

      // Get the size of the message.
      let messageSize = buffer.readableBytes

      // Move the reader index back 5 bytes. This is okay: we validated the `readerIndex` above.
      buffer.moveReaderIndex(to: buffer.readerIndex - 5)

      // Fill in the compression byte and message length.
      buffer.setInteger(UInt8(0), at: buffer.readerIndex)
      buffer.setInteger(UInt32(messageSize), at: buffer.readerIndex + 1)

      // The message bytes are already in place, we're done.
      return buffer
    } else {
      // We're not compressing and we don't have enough space before the message bytes passed in.
      // We need a new buffer.
      var lengthPrefixed = allocator.buffer(capacity: 5 + buffer.readableBytes)

      // Write the compression byte.
      lengthPrefixed.writeInteger(UInt8(0))

      // Write the message length.
      lengthPrefixed.writeInteger(UInt32(buffer.readableBytes))

      // Write the message.
      var buffer = buffer
      lengthPrefixed.writeBuffer(&buffer)

      return lengthPrefixed
    }
  }

  /// Writes the data into a `ByteBuffer` as a gRPC length-prefixed message.
  ///
  /// - Parameters:
  ///   - payload: The payload to serialize and write.
  ///   - buffer: The buffer to write the message into.
  /// - Returns: A `ByteBuffer` containing a gRPC length-prefixed message.
  /// - Precondition: `compression.supported` is `true`.
  /// - Note: See `LengthPrefixedMessageReader` for more details on the format.
  func write(_ payload: GRPCPayload, into buffer: inout ByteBuffer,
             compressed: Bool = true) throws {
    buffer.reserveCapacity(buffer.writerIndex + LengthPrefixedMessageWriter.metadataLength)

    if compressed, let compressor = self.compressor {
      // Set the compression byte.
      buffer.writeInteger(UInt8(1))

      // Leave a gap for the length, we'll set it in a moment.
      let payloadSizeIndex = buffer.writerIndex
      buffer.moveWriterIndex(forwardBy: MemoryLayout<UInt32>.size)

      var messageBuf = ByteBufferAllocator().buffer(capacity: 0)
      try payload.serialize(into: &messageBuf)

      // Compress the message.
      let bytesWritten = try compressor.deflate(&messageBuf, into: &buffer)

      // Now fill in the message length.
      buffer.writePayloadLength(UInt32(bytesWritten), at: payloadSizeIndex)

      // Finally, the compression context should be reset between messages.
      compressor.reset()
    } else {
      // We could be using 'identity' compression, but since the result is the same we'll just
      // say it isn't compressed.
      buffer.writeInteger(UInt8(0))

      // Leave a gap for the length, we'll set it in a moment.
      let payloadSizeIndex = buffer.writerIndex
      buffer.moveWriterIndex(forwardBy: MemoryLayout<UInt32>.size)

      let payloadPrefixedBytes = buffer.readableBytes
      // Writes the payload into the buffer
      try payload.serialize(into: &buffer)

      // Calculates the Written bytes with respect to the prefixed ones
      let bytesWritten = buffer.readableBytes - payloadPrefixedBytes

      // Write the message length.
      buffer.writePayloadLength(UInt32(bytesWritten), at: payloadSizeIndex)
    }
  }
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
