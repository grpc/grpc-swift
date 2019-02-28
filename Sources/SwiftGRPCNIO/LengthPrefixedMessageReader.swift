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
/// Messages may span multiple `ByteBuffer`s, and `ByteBuffer`s may contain multiple
/// length-prefixed messages.
///
/// - SeeAlso:
/// [gRPC Protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
public class LengthPrefixedMessageReader {
  public typealias Mode = GRPCError.Origin

  private let mode: Mode
  private var buffer: ByteBuffer!
  private var state: State = .expectingCompressedFlag

  private enum State {
    case expectingCompressedFlag
    case expectingMessageLength
    case receivedMessageLength(Int)
    case willBuffer(requiredBytes: Int)
    case isBuffering(requiredBytes: Int)
  }

  public init(mode: Mode) {
    self.mode = mode
  }

  /// Consumes all readable bytes from given buffer and returns all messages which could be read.
  ///
  /// - SeeAlso: `read(messageBuffer:compression:)`
  public func consume(messageBuffer: inout ByteBuffer, compression: CompressionMechanism) throws -> [ByteBuffer] {
    var messages: [ByteBuffer] = []

    while messageBuffer.readableBytes > 0 {
      if let message = try self.read(messageBuffer: &messageBuffer, compression: compression) {
        messages.append(message)
      }
    }

    return messages
  }

  /// Reads bytes from the given buffer until it is exhausted or a message has been read.
  ///
  /// Length prefixed messages may be split across multiple input buffers in any of the
  /// following places:
  /// 1. after the compression flag,
  /// 2. after the message length field,
  /// 3. at any point within the message.
  ///
  /// It is possible for the message length field to be split across multiple `ByteBuffer`s,
  /// this is unlikely to happen in practice.
  ///
  /// - Note:
  /// This method relies on state; if a message is _not_ returned then the next time this
  /// method is called it expects to read the bytes which follow the most recently read bytes.
  ///
  /// - Parameters:
  ///   - messageBuffer: buffer to read from.
  ///   - compression: compression mechanism to decode message with.
  /// - Returns: A buffer containing a message if one has been read, or `nil` if not enough
  ///   bytes have been consumed to return a message.
  /// - Throws: Throws an error if the compression algorithm is not supported.
  public func read(messageBuffer: inout ByteBuffer, compression: CompressionMechanism) throws -> ByteBuffer? {
    while true {
      switch state {
      case .expectingCompressedFlag:
        guard let compressionFlag: Int8 = messageBuffer.readInteger() else { return nil }
        try handleCompressionFlag(enabled: compressionFlag != 0, mechanism: compression)
        self.state = .expectingMessageLength

      case .expectingMessageLength:
        //! FIXME: Support the message length being split across multiple byte buffers.
        guard let messageLength: UInt32 = messageBuffer.readInteger() else { return nil }
        self.state = .receivedMessageLength(numericCast(messageLength))

      case .receivedMessageLength(let messageLength):
        // If this holds true, we can skip buffering and return a slice.
        guard messageLength <= messageBuffer.readableBytes else {
          self.state = .willBuffer(requiredBytes: messageLength)
          continue
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
      throw GRPCError.common(.unexpectedCompression, origin: mode)
    }

    guard mechanism.supported else {
      throw GRPCError.common(.unsupportedCompressionMechanism(mechanism.rawValue), origin: mode)
    }
  }
}
