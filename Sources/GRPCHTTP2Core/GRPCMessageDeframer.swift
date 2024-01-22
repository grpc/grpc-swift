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
import GRPCCore

/// A ``GRPCMessageDeframer`` helps with the deframing of gRPC data frames:
/// - It reads the frame's metadata to know whether the message payload is compressed or not, and its length
/// - It reads and decompresses the payload, if compressed
/// - It helps put together frames that have been split across multiple `ByteBuffers` by the underlying transport
struct GRPCMessageDeframer: NIOSingleStepByteToMessageDecoder {
  /// Length of the gRPC message header (1 compression byte, 4 bytes for the length).
  static let metadataLength = 5
  static let defaultMaximumPayloadSize = Int.max

  typealias InboundOut = [UInt8]
  
  private let decompressor: Zlib.Decompressor?
  private let maximumPayloadSize: Int?
  private var effectiveMaximumPayloadSize: Int {
    self.maximumPayloadSize ?? Self.defaultMaximumPayloadSize
  }
  
  /// Create a new ``GRPCMessageDeframer``.
  /// - Parameters:
  ///   - maximumPayloadSize: The maximum size a message payload can be.
  ///   - decompressor: A `Zlib.Decompressor` to use when decompressing compressed gRPC messages.
  /// - Important: You must call `end()` on the `decompressor` when you're done using it, to clean
  /// up any resources allocated by `Zlib`.
  init(maximumPayloadSize: Int? = nil, decompressor: Zlib.Decompressor? = nil) {
    self.maximumPayloadSize = maximumPayloadSize
    self.decompressor = decompressor
  }
  
  mutating func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
    guard buffer.readableBytes >= Self.metadataLength else {
      // If we cannot read enough bytes to cover the metadata's length, then we
      // need to wait for more bytes to become available to us.
      return nil
    }

    // Store the current reader index in case we don't yet have enough
    // bytes in the buffer to decode a full frame, and need to reset it.
    let originalReaderIndex = buffer.readerIndex
    let isMessageCompressed = buffer.readInteger(as: UInt8.self)! == 1

    guard var message = buffer.readLengthPrefixedSlice(as: UInt32.self) else {
      // We have moved the reader index, but we don't have enough bytes to
      // read the full message payload, so reset it to its previous, original
      // position for now, and return. We'll try decoding again, once more
      // bytes become available in our buffer.
      buffer.moveReaderIndex(to: originalReaderIndex)
      return nil
    }
    
    if isMessageCompressed {
      guard let decompressor = self.decompressor else {
        // We cannot decompress the payload - discard the message.
        return nil
      }
      return try decompressor.decompress(&message, limit: self.effectiveMaximumPayloadSize)
    } else {
      if message.readableBytes > self.effectiveMaximumPayloadSize {
        throw RPCError(
          code: .resourceExhausted,
          message: "Message has exceeded the configured maximum payload size (max: \(self.effectiveMaximumPayloadSize), actual: \(message.readableBytes))"
        )
      }
      return Array(buffer: message)
    }
  }
  
  mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
    try self.decode(buffer: &buffer)
  }
}
