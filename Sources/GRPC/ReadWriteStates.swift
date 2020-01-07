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
import NIO
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

  /// The compression used when writing messages.
  var compression: CompressionAlgorithm?

  /// The 'content-type' being written.
  var contentType: ContentType

  func makeWriteState() -> WriteState {
    return .writing(
      self.arity,
      self.contentType,
      LengthPrefixedMessageWriter(compression: self.compression)
    )
  }
}

/// The write state of a stream.
enum WriteState {
  /// Writing may be attempted using the given writer.
  case writing(MessageArity, ContentType, LengthPrefixedMessageWriter)

  /// Writing may not be attempted: either a write previously failed or it is not valid for any
  /// more messages to be written.
  case notWriting

  /// Writes a message into a buffer using the `writer` and `allocator`.
  ///
  /// - Parameter message: The `Message` to write.
  /// - Parameter allocator: An allocator to provide a `ByteBuffer` into which the message will be
  ///     written.
  mutating func write(
    _ message: Message,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    switch self {
    case .notWriting:
      return .failure(.cardinalityViolation)

    case let .writing(writeArity, contentType, writer):
      guard let data = try? message.serializedData() else {
        self = .notWriting
        return .failure(.serializationFailed)
      }

      // Zero is fine: the writer will allocate the correct amount of space.
      var buffer = allocator.buffer(capacity: 0)
      writer.write(data, into: &buffer)

      // If we only expect to write one message then we're no longer writable.
      if case .one = writeArity {
        self = .notWriting
      } else {
        self = .writing(writeArity, contentType, writer)
      }

      return .success(buffer)
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

/// The read state of a stream.
enum ReadState {
  /// Reading may be attempted using the given reader.
  case reading(MessageArity, LengthPrefixedMessageReader)

  /// Reading may not be attempted: either a read previously failed or it is not valid for any
  /// more messages to be read.
  case notReading

  /// Consume the given `buffer` then attempt to read and subsequently decode length-prefixed
  /// serialized messages.
  ///
  /// For an expected message count of `.one`, this function will produce **at most** 1 message. If
  /// a message has been produced then subsequent calls will result in an error.
  ///
  /// - Parameter buffer: The buffer to read from.
  mutating func readMessages<MessageType: Message>(
    _ buffer: inout ByteBuffer,
    as: MessageType.Type = MessageType.self
  ) -> Result<[MessageType], MessageReadError> {
    switch self {
    case .notReading:
      return .failure(.cardinalityViolation)

    case .reading(let readArity, var reader):
      reader.append(buffer: &buffer)
      var messages: [MessageType] = []

      do {
        while var serializedBytes = try? reader.nextMessage() {
          // Force unwrapping is okay here: we will always be able to read `readableBytes`.
          let serializedData = serializedBytes.readData(length: serializedBytes.readableBytes)!
          messages.append(try MessageType(serializedData: serializedData))
        }
      } catch {
        self = .notReading
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

enum MessageReadError: Error {
  /// Too many messages were read.
  case cardinalityViolation

  /// Enough messages were read but bytes there are left-over bytes.
  case leftOverBytes

  /// Message deserialization failed.
  case deserializationFailed

  /// An invalid state was encountered. This is a serious implementation error.
  case invalidState
}
