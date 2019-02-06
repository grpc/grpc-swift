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
import NIOHTTP1

/// This class reads and decodes length-prefixed gRPC messages.
///
/// Messages are expected to be in the following format:
/// - compression flag: 0/1 as a 1-byte unsigned integer,
/// - message length: length of the message as a 4-byte unsigned integer,
/// - message: `message_length` bytes.
///
/// - SeeAlso:
/// [gRPC Protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
internal class LengthPrefixedMessageReader {
  private var buffer: ByteBuffer!
  private var state: State = .expectingCompressedFlag
  private let mode: Mode

  internal init(mode: Mode) {
    self.mode = mode
  }

  internal enum Mode { case client, server }

  private enum State {
    case expectingCompressedFlag
    case expectingMessageLength
    case receivedMessageLength(Int)
    case willBuffer(requiredBytes: Int)
    case isBuffering(requiredBytes: Int)
  }

  /// Reads bytes from the given buffer until it is exhausted or a message has been read.
  ///
  /// Length prefixed messages may be split across multiple input buffers in any of the
  /// following places:
  /// 1. after the compression flag,
  /// 2. after the message length flag,
  /// 3. at any point within the message.
  ///
  /// - Note:
  /// This method relies on state; if a message is _not_ returned then the next time this
  /// method is called it expect to read the bytes which follow the most recently read bytes.
  /// If a message _is_ returned without exhausting the given buffer then reading a
  /// different buffer is not an issue.
  ///
  /// - Parameter messageBuffer: buffer to read from.
  /// - Returns: A buffer containing a message if one has been read, or `nil` if not enough
  ///   bytes have been consumed to return a message.
  /// - Throws: Throws an error if the compression algorithm is not supported.
  internal func read(messageBuffer: inout ByteBuffer, compression: CompressionMechanism) throws -> ByteBuffer? {
    while true {
      switch state {
      case .expectingCompressedFlag:
        guard let compressionFlag: Int8 = messageBuffer.readInteger() else { return nil }
        try handleCompressionFlag(enabled: compressionFlag != 0, mechanism: compression)
        self.state = .expectingMessageLength

      case .expectingMessageLength:
        guard let messageLength: UInt32 = messageBuffer.readInteger() else { return nil }
        self.state = .receivedMessageLength(numericCast(messageLength))

      case .receivedMessageLength(let messageLength):
        // If this holds true, we can skip buffering and return a slice.
        guard messageLength <= messageBuffer.readableBytes else {
          self.state = .willBuffer(requiredBytes: messageLength)
          break
        }

        self.state = .expectingCompressedFlag
        // We know messageBuffer.readableBytes >= messageLength, so it's okay to force unwrap here.
        return messageBuffer.readSlice(length: messageLength)!

      case .willBuffer(let requiredBytes):
        messageBuffer.reserveCapacity(requiredBytes)
        self.buffer = messageBuffer

        let readableBytes = messageBuffer.readableBytes
        // Move the reader index to avoid reading the bytes again.
        messageBuffer.moveReaderIndex(forwardBy: readableBytes)

        self.state = .isBuffering(requiredBytes: requiredBytes - readableBytes)
        return nil

      case .isBuffering(let requiredBytes):
        guard requiredBytes <= messageBuffer.readableBytes else {
          self.state = .isBuffering(requiredBytes: requiredBytes - self.buffer.write(buffer: &messageBuffer))
          return nil
        }

        // We know messageBuffer.readableBytes >= requiredBytes, so it's okay to force unwrap here.
        var slice = messageBuffer.readSlice(length: requiredBytes)!
        self.buffer.write(buffer: &slice)
        self.state = .expectingCompressedFlag

        defer { self.buffer = nil }
        return buffer
      }
    }
  }

  private func handleCompressionFlag(enabled flagEnabled: Bool, mechanism: CompressionMechanism) throws {
    guard flagEnabled == mechanism.requiresFlag else {
      throw GRPCStatus.processingError
    }

    guard mechanism.supported else {
      throw GRPCStatus(code: .unimplemented, message: "\(mechanism) compression is not currently supported on the \(mode)")
    }
  }
}
