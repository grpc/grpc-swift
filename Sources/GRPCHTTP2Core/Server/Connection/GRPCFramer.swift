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

/// A ``GRPCFramer`` helps with the framing of gRPC data frames:
/// - It prepends data with the required metadata (compression flag and message length).
/// - It compresses messages using the specified compression algorithm (if configured).
/// - It coalesces multiple messages (appended into the `Framer` by calling ``append(_:compress:)``)
/// into a single `ByteBuffer`.
struct GRPCFramer {
  /// Length of the gRPC message header (1 compression byte, 4 bytes for the length).
  static let metadataLength = 5

  private var pendingMessages: OneOrManyQueue<PendingMessage>

  private struct PendingMessage {
    let bytes: [UInt8]
    let isCompressed: Bool
  }

  private var writeBuffer: ByteBuffer

  init() {
    self.pendingMessages = OneOrManyQueue()
    self.writeBuffer = ByteBuffer()
    self.writeBuffer.reserveCapacity(minimumWritableBytes: Self.metadataLength)
  }

  /// Queue the given bytes to be framed and potentially coalesced alongside other messages in a `ByteBuffer`.
  /// The resulting data will be returned when calling ``GRPCFramer/next()``.
  /// If `compress` is true, then the given bytes will be compressed using the configured compression algorithm.
  /// - Throws: If compression fails, an error will be thrown.
  mutating func append(_ bytes: [UInt8], compress: Bool) throws {
    if compress {
      // TODO: compress bytes before creating the PendingMessage once we've got a Compressor.
    } else {
      self.pendingMessages.append(PendingMessage(bytes: bytes, isCompressed: compress))
    }
  }

  /// If there are pending messages to be framed, a `ByteBuffer` will be returned with the framed data.
  /// Data may also be compressed (if configured) and multiple frames may be coalesced into the same `ByteBuffer`.
  mutating func next() -> ByteBuffer? {
    if self.pendingMessages.isEmpty {
      // Nothing pending: exit early.
      return nil
    }

    var requiredCapacity = 0
    for message in self.pendingMessages {
      // TODO: Maybe we should add some break condition here, e.g. a max buffer size
      // or max number of messages to include in the same buffer, but I'm unsure what
      // this number should be.
      requiredCapacity += message.bytes.count + Self.metadataLength
    }
    self.writeBuffer.clear(minimumCapacity: requiredCapacity)

    while let message = self.pendingMessages.pop() {
      self.encode(message)
    }

    return self.writeBuffer
  }

  mutating private func encode(_ message: PendingMessage) {
    self.writeBuffer.writeMultipleIntegers(
      UInt8(message.isCompressed ? 1 : 0),
      UInt32(message.bytes.count)
    )
    self.writeBuffer.writeBytes(message.bytes)
  }
}
