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
import Logging
import NIOCore
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
internal struct LengthPrefixedMessageReader {
  let compression: CompressionAlgorithm?
  private let decompressor: Zlib.Inflate?

  init() {
    self.compression = nil
    self.decompressor = nil
  }

  init(compression: CompressionAlgorithm, decompressionLimit: DecompressionLimit) {
    self.compression = compression

    switch compression.algorithm {
    case .identity:
      self.decompressor = nil
    case .deflate:
      self.decompressor = Zlib.Inflate(format: .deflate, limit: decompressionLimit)
    case .gzip:
      self.decompressor = Zlib.Inflate(format: .gzip, limit: decompressionLimit)
    }
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
    case expectingMessageLength(compressed: Bool)
    case expectingMessage(Int, compressed: Bool)
  }

  private var buffer: ByteBuffer!
  private var state: ParseState = .expectingCompressedFlag

  /// Returns the number of unprocessed bytes.
  internal var unprocessedBytes: Int {
    return self.buffer.map { $0.readableBytes } ?? 0
  }

  /// Returns the number of bytes that have been consumed and not discarded.
  internal var _consumedNonDiscardedBytes: Int {
    return self.buffer.map { $0.readerIndex } ?? 0
  }

  /// Whether the reader is mid-way through reading a message.
  internal var isReading: Bool {
    switch self.state {
    case .expectingCompressedFlag:
      return false
    case .expectingMessageLength, .expectingMessage:
      return true
    }
  }

  /// Appends data to the buffer from which messages will be read.
  internal mutating func append(buffer: inout ByteBuffer) {
    guard buffer.readableBytes > 0 else {
      return
    }

    if self.buffer == nil {
      self.buffer = buffer.slice()
      // mark the bytes as "read"
      buffer.moveReaderIndex(forwardBy: buffer.readableBytes)
    } else {
      switch self.state {
      case let .expectingMessage(length, _):
        // We need to reserve enough space for the message or the incoming buffer, whichever
        // is larger.
        let remainingMessageBytes = Int(length) - self.buffer.readableBytes
        self.buffer
          .reserveCapacity(minimumWritableBytes: max(remainingMessageBytes, buffer.readableBytes))

      case .expectingCompressedFlag,
        .expectingMessageLength:
        // Just append the buffer; these parts are too small to make a meaningful difference.
        ()
      }

      self.buffer.writeBuffer(&buffer)
    }
  }

  /// Reads bytes from the buffer until it is exhausted or a message has been read.
  ///
  /// - Returns: A buffer containing a message if one has been read, or `nil` if not enough
  ///   bytes have been consumed to return a message.
  /// - Throws: Throws an error if the compression algorithm is not supported.
  internal mutating func nextMessage(maxLength: Int) throws -> ByteBuffer? {
    switch try self.processNextState(maxLength: maxLength) {
    case .needMoreData:
      self.nilBufferIfPossible()
      return nil

    case .continue:
      return try self.nextMessage(maxLength: maxLength)

    case let .message(message):
      self.nilBufferIfPossible()
      return message
    }
  }

  /// `nil`s out `buffer` if it exists and has no readable bytes.
  ///
  /// This allows the next call to `append` to avoid writing the contents of the appended buffer.
  private mutating func nilBufferIfPossible() {
    let readableBytes = self.buffer?.readableBytes ?? 0
    let readerIndex = self.buffer?.readerIndex ?? 0
    let capacity = self.buffer?.capacity ?? 0

    if readableBytes == 0 {
      self.buffer = nil
    } else if readerIndex > 1024, readerIndex > (capacity / 2) {
      // A rough-heuristic: if there is a kilobyte of read data, and there is more data that
      // has been read than there is space in the rest of the buffer, we'll try to discard some
      // read bytes here. We're trying to avoid doing this if there is loads of writable bytes that
      // we'll have to shift.
      self.buffer?.discardReadBytes()
    }
  }

  private mutating func processNextState(maxLength: Int) throws -> ParseResult {
    guard self.buffer != nil else {
      return .needMoreData
    }

    switch self.state {
    case .expectingCompressedFlag:
      guard let compressionFlag: UInt8 = self.buffer.readInteger() else {
        return .needMoreData
      }

      let isCompressionEnabled = compressionFlag != 0
      // Compression is enabled, but not expected.
      if isCompressionEnabled, self.compression == nil {
        throw GRPCError.CompressionUnsupported().captureContext()
      }
      self.state = .expectingMessageLength(compressed: isCompressionEnabled)

    case let .expectingMessageLength(compressed):
      guard let messageLength = self.buffer.readInteger(as: UInt32.self).map(Int.init) else {
        return .needMoreData
      }

      if messageLength > maxLength {
        throw GRPCError.PayloadLengthLimitExceeded(
          actualLength: messageLength,
          limit: maxLength
        ).captureContext()
      }

      self.state = .expectingMessage(messageLength, compressed: compressed)

    case let .expectingMessage(length, compressed):
      guard var message = self.buffer.readSlice(length: length) else {
        return .needMoreData
      }

      let result: ParseResult

      // TODO: If compression is enabled and we store the buffer slices then we can feed the slices
      // into the decompressor. This should eliminate one buffer allocation (i.e. the buffer into
      // which we currently accumulate the slices before decompressing it into a new buffer).

      // If compression is set but the algorithm is 'identity' then we will not get a decompressor
      // here.
      if compressed, let decompressor = self.decompressor {
        var decompressed = ByteBufferAllocator().buffer(capacity: 0)
        try decompressor.inflate(&message, into: &decompressed)
        // Compression contexts should be reset between messages.
        decompressor.reset()
        result = .message(decompressed)
      } else {
        result = .message(message)
      }

      self.state = .expectingCompressedFlag
      return result
    }

    return .continue
  }
}
