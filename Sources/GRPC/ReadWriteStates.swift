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
import NIOCore
import SwiftProtobuf

/// Number of messages expected on a stream.
enum MessageArity {
  case one
  case many
}

/// Encapsulates the state required to create a new write state.
struct PendingWriteState {
  /// The number of messages we expect to write to the stream.
  var arity: MessageArity

  /// The 'content-type' being written.
  var contentType: ContentType

  func makeWriteState(
    messageEncoding: ClientMessageEncoding,
    allocator: ByteBufferAllocator
  ) -> WriteState {
    let compression: CompressionAlgorithm?
    switch messageEncoding {
    case let .enabled(configuration):
      compression = configuration.outbound
    case .disabled:
      compression = nil
    }

    let writer = CoalescingLengthPrefixedMessageWriter(
      compression: compression,
      allocator: allocator
    )
    return .init(arity: self.arity, contentType: self.contentType, writer: writer)
  }
}

/// The write state of a stream.
struct WriteState {
  private var arity: MessageArity
  private var contentType: ContentType
  private var writer: CoalescingLengthPrefixedMessageWriter
  private var canWrite: Bool

  init(
    arity: MessageArity,
    contentType: ContentType,
    writer: CoalescingLengthPrefixedMessageWriter
  ) {
    self.arity = arity
    self.contentType = contentType
    self.writer = writer
    self.canWrite = true
  }

  /// Writes a message into a buffer using the `writer`.
  ///
  /// - Parameter message: The `Message` to write.
  mutating func write(
    _ message: ByteBuffer,
    compressed: Bool,
    promise: EventLoopPromise<Void>?
  ) -> Result<Void, MessageWriteError> {
    guard self.canWrite else {
      return .failure(.cardinalityViolation)
    }

    self.writer.append(buffer: message, compress: compressed, promise: promise)

    switch self.arity {
    case .one:
      self.canWrite = false
    case .many:
      ()
    }

    return .success(())
  }

  mutating func next() -> (Result<ByteBuffer, MessageWriteError>, EventLoopPromise<Void>?)? {
    if let next = self.writer.next() {
      return (next.0.mapError { _ in .serializationFailed }, next.1)
    } else {
      return nil
    }
  }
}

enum MessageWriteError: Error {
  /// Too many messages were written.
  case cardinalityViolation

  /// Message serialization failed.
  case serializationFailed

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}

/// Encapsulates the state required to create a new read state.
struct PendingReadState {
  /// The number of messages we expect to read from the stream.
  var arity: MessageArity

  /// The message encoding configuration, and whether it's enabled or not.
  var messageEncoding: ClientMessageEncoding

  func makeReadState(compression: CompressionAlgorithm? = nil) -> ReadState {
    let reader: LengthPrefixedMessageReader
    switch (self.messageEncoding, compression) {
    case let (.enabled(configuration), .some(compression)):
      reader = LengthPrefixedMessageReader(
        compression: compression,
        decompressionLimit: configuration.decompressionLimit
      )

    case (.enabled, .none),
         (.disabled, _):
      reader = LengthPrefixedMessageReader()
    }
    return .reading(self.arity, reader)
  }
}

/// The read state of a stream.
enum ReadState {
  /// Reading may be attempted using the given reader.
  case reading(MessageArity, LengthPrefixedMessageReader)

  /// Reading may not be attempted: either a read previously failed or it is not valid for any
  /// more messages to be read.
  case notReading

  /// Consume the given `buffer` then attempt to read length-prefixed serialized messages.
  ///
  /// For an expected message count of `.one`, this function will produce **at most** 1 message. If
  /// a message has been produced then subsequent calls will result in an error.
  ///
  /// - Parameter buffer: The buffer to read from.
  mutating func readMessages(
    _ buffer: inout ByteBuffer,
    maxLength: Int
  ) -> Result<[ByteBuffer], MessageReadError> {
    switch self {
    case .notReading:
      return .failure(.cardinalityViolation)

    case .reading(let readArity, var reader):
      self = .notReading // Avoid CoWs
      reader.append(buffer: &buffer)
      var messages: [ByteBuffer] = []

      do {
        while let serializedBytes = try reader.nextMessage(maxLength: maxLength) {
          messages.append(serializedBytes)
        }
      } catch {
        self = .notReading
        if let grpcError = error as? GRPCError.WithContext {
          if let compressionLimit = grpcError.error as? GRPCError.DecompressionLimitExceeded {
            return .failure(.decompressionLimitExceeded(compressionLimit.compressedSize))
          } else if let lengthLimit = grpcError.error as? GRPCError.PayloadLengthLimitExceeded {
            return .failure(.lengthExceedsLimit(lengthLimit))
          }
        }

        return .failure(.deserializationFailed)
      }

      // We need to validate the number of messages we decoded. Zero is fine because the payload may
      // be split across frames.
      switch (readArity, messages.count) {
      // Always allowed:
      case (.one, 0),
           (.many, 0...):
        self = .reading(readArity, reader)
        return .success(messages)

      // Also allowed, assuming we have no leftover bytes:
      case (.one, 1):
        // We can't read more than one message on a unary stream.
        self = .notReading
        // We shouldn't have any bytes leftover after reading a single message and we also should not
        // have partially read a message.
        if reader.unprocessedBytes != 0 || reader.isReading {
          return .failure(.leftOverBytes)
        } else {
          return .success(messages)
        }

      // Anything else must be invalid.
      default:
        self = .notReading
        return .failure(.cardinalityViolation)
      }
    }
  }
}

enum MessageReadError: Error, Equatable {
  /// Too many messages were read.
  case cardinalityViolation

  /// Enough messages were read but bytes there are left-over bytes.
  case leftOverBytes

  /// Message deserialization failed.
  case deserializationFailed

  /// The limit for decompression was exceeded.
  case decompressionLimitExceeded(Int)

  /// The length of the message exceeded the permitted maximum length.
  case lengthExceedsLimit(GRPCError.PayloadLengthLimitExceeded)

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}
