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
import Logging

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
  let logger: Logger

  /// The mechanism that messages will be compressed with.
  public var compressionMechanism: CompressionMechanism

  public init(mode: Mode, compressionMechanism: CompressionMechanism, logger: Logger) {
    self.mode = mode
    self.compressionMechanism = compressionMechanism
    self.logger = logger
  }

  /// The result of trying to parse a message with the bytes we currently have.
  ///
  /// - needMoreData: More data is required to continue reading a message.
  /// - continue: Continue reading a message.
  /// - message: A message was read.
  internal enum ParseResult {
    case needMoreData
    case `continue`
    case message(ByteBuffer)
  }

  /// The parsing state; what we expect to be reading next.
  internal enum ParseState {
    case expectingCompressedFlag
    case expectingMessageLength
    case expectingMessage(UInt32)
  }

  private let mode: Mode
  private var buffer: ByteBuffer!
  private var state: ParseState = .expectingCompressedFlag {
    didSet {
      self.logger.debug("parse state changed from \(oldValue) to \(self.state)")
    }
  }

  /// Appends data to the buffer from which messages will be read.
  public func append(buffer: inout ByteBuffer) {
    self.logger.info("appending \(buffer.readableBytes) bytes to buffer")
    if self.buffer == nil {
      self.logger.debug("creating new buffer from slice")
      self.buffer = buffer.slice()
      // mark the bytes as "read"
      buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
    } else {
      self.logger.debug("copying bytes into existing buffer")
      self.buffer.writeBuffer(&buffer)
    }
  }

  /// Reads bytes from the buffer until it is exhausted or a message has been read.
  ///
  /// - Returns: A buffer containing a message if one has been read, or `nil` if not enough
  ///   bytes have been consumed to return a message.
  /// - Throws: Throws an error if the compression algorithm is not supported.
  public func nextMessage() throws -> ByteBuffer? {
    switch try self.processNextState() {
    case .needMoreData:
      self.nilBufferIfPossible()
      return nil

    case .continue:
      return try nextMessage()

    case .message(let message):
      self.logger.info("read length-prefixed message")
      self.nilBufferIfPossible()
      return message
    }
  }

  /// `nil`s out `buffer` if it exists and has no readable bytes.
  ///
  /// This allows the next call to `append` to avoid writing the contents of the appended buffer.
  private func nilBufferIfPossible() {
    if self.buffer?.readableBytes == 0 {
      self.logger.debug("no readable bytes; nilling-out buffer")
      self.buffer = nil
    }
  }

  private func processNextState() throws -> ParseResult {
    guard self.buffer != nil else {
      self.logger.debug("no buffer to read from")
      return .needMoreData
    }

    switch self.state {
    case .expectingCompressedFlag:
      guard let compressionFlag: Int8 = self.buffer.readInteger() else {
        self.logger.debug("1 more byte needed to read compression flag")
        return .needMoreData
      }
      self.logger.debug("read 1 byte compression flag: \(compressionFlag)")
      try self.handleCompressionFlag(enabled: compressionFlag != 0)
      self.state = .expectingMessageLength

    case .expectingMessageLength:
      guard let messageLength: UInt32 = self.buffer.readInteger() else {
        self.logger.debug("\(4 - buffer.readableBytes) more bytes needed to read message length")
        return .needMoreData
      }
      self.logger.debug("read 4 byte message length: \(messageLength)")
      self.state = .expectingMessage(messageLength)

    case .expectingMessage(let length):
      let signedLength: Int = numericCast(length)
      guard let message = self.buffer.readSlice(length: signedLength) else {
        self.logger.debug("\(signedLength - buffer.readableBytes) more bytes needed to read message")
        return .needMoreData
      }
      self.logger.debug("read \(message.readableBytes) byte message")
      self.state = .expectingCompressedFlag
      return .message(message)
    }

    return .continue
  }

  private func handleCompressionFlag(enabled flagEnabled: Bool) throws {
    guard flagEnabled else {
      self.logger.debug("compression is not enabled for this message")
      return
    }
    self.logger.info("compression is enabled for this message")

    guard self.compressionMechanism.requiresFlag else {
      self.logger.error("compression flag was set but '\(self.compressionMechanism)' does not require it")
      throw GRPCError.common(.unexpectedCompression, origin: mode)
    }

    guard self.compressionMechanism.supported else {
      self.logger.error("compression mechanism '\(self.compressionMechanism)' is not supported")
      throw GRPCError.common(.unsupportedCompressionMechanism(compressionMechanism.rawValue), origin: mode)
    }
  }
}
