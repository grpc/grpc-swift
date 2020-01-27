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
import NIO

internal struct LengthPrefixedMessageWriter {
  static let metadataLength = 5

  /// The compression algorithm to use, if one should be used.
  private let compression: CompressionAlgorithm?
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

  /// Writes the data into a `ByteBuffer` as a gRPC length-prefixed message.
  ///
  /// - Parameters:
  ///   - message: The serialized Protobuf message to write.
  ///   - buffer: The buffer to write the message into.
  /// - Returns: A `ByteBuffer` containing a gRPC length-prefixed message.
  /// - Precondition: `compression.supported` is `true`.
  /// - Note: See `LengthPrefixedMessageReader` for more details on the format.
  func write(_ message: Data, into buffer: inout ByteBuffer, disableCompression: Bool = false) throws {
    buffer.reserveCapacity(LengthPrefixedMessageWriter.metadataLength + message.count)

    if !disableCompression, let compressor = self.compressor {
      // Set the compression byte.
      buffer.writeInteger(UInt8(1))

      // Leave a gap for the length, we'll set it in a moment.
      let payloadSizeIndex = buffer.writerIndex
      buffer.moveWriterIndex(forwardBy: MemoryLayout<UInt32>.size)

      // Compress the message.
      var message = message
      let bytesWritten = try compressor.deflate(&message, into: &buffer)

      // Now fill in the message length.
      buffer.writePayloadLength(UInt32(bytesWritten), at: payloadSizeIndex)

      // Finally, the compression context should be reset between messages.
      compressor.reset()
    } else {
      // 'identity' compression has no compressor but should still set the compression bit set
      // unless we explicitly disable compression.
      if self.compression?.algorithm == .identity && !disableCompression {
        buffer.writeInteger(UInt8(1))
      } else {
        buffer.writeInteger(UInt8(0))
      }

      // Write the message length.
      buffer.writeInteger(UInt32(message.count))
      // And the message bytes.
      buffer.writeBytes(message)
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
