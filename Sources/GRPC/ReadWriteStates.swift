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
  case none
  case one
  case many
}

/// Encapsulates the state required to create a new write state.
struct PendingWriteState {
  /// The number of messages we expect to write to the stream.
  var arity: MessageArity

  /// The encoding we should use when writing the message.
  var encoding: CompressionMechanism

  /// The 'content-type' being written.
  var contentType: ContentType

  func makeWriteState() -> WriteState {
    return WriteState(
      arity: self.arity,
      writer: LengthPrefixedMessageWriter(compression: self.encoding),
      contentType: self.contentType
    )
  }
}

/// The write state of a stream.
struct WriteState {
  /// Whether the stream may be written to.
  internal var canWrite: Bool {
    return self.arity != .none
  }

  /// The number of messages we expect to write to the stream.
  var arity: MessageArity

  /// A writer to encode `Message`s into the gRPC wire-format.
  var writer: LengthPrefixedMessageWriter

  /// The 'content-type' being written.
  var contentType: ContentType

  init(arity: MessageArity, writer: LengthPrefixedMessageWriter, contentType: ContentType) {
    self.arity = arity
    self.writer = writer
    self.contentType = contentType
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

extension WriteState {
  /// Writes a message into a buffer using the `writer` and `allocator`.
  ///
  /// - Parameter message: The `Message` to write.
  /// - Parameter allocator: An allocator to provide a `ByteBuffer` into which the message will be
  ///     written.
  mutating func write(
    _ message: Message,
    allocator: ByteBufferAllocator
  ) -> Result<ByteBuffer, MessageWriteError> {
    guard self.canWrite else {
      return .failure(.cardinalityViolation)
    }

    guard let data = try? message.serializedData() else {
      return .failure(.serializationFailed)
    }

    // Zero is fine: the writer will allocate the correct amount of space.
    var buffer = allocator.buffer(capacity: 0)
    self.writer.write(data, into: &buffer)

    // If we only expect to write one message then we're no longer writable.
    if case .one = self.arity {
      self.arity = .none
    }

    return .success(buffer)
  }
}

/// The read state of a stream.
struct ReadState {
  /// Whether the stream may read.
  internal var canRead: Bool {
    return self.arity != .none
  }

  /// The expected number of messages of the reading stream.
  var arity: MessageArity

  /// A reader which accepts bytes in the gRPC wire-format and produces sequences of bytes which
  /// may be decoded into protobuf `Message`s.
  var reader: LengthPrefixedMessageReader

  init(arity: MessageArity, reader: LengthPrefixedMessageReader) {
    self.arity = arity
    self.reader = reader
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

extension ReadState {
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
    guard self.canRead else {
      return .failure(.cardinalityViolation)
    }

    self.reader.append(buffer: &buffer)
    var messages: [MessageType] = []

    // Pull out as many messages from the reader as possible.
    do {
      while var serializedBytes = try? self.reader.nextMessage() {
        // Force unwrapping is okay here: we will always be able to read `readableBytes`.
        let serializedData = serializedBytes.readData(length: serializedBytes.readableBytes)!
        messages.append(try MessageType(serializedData: serializedData))
      }
    } catch {
      return .failure(.deserializationFailed)
    }

    // We need to validate the number of messages we decoded. Zero is fine because the payload may
    // be split across frames.
    switch (self.arity, messages.count) {
    // Always allowed:
    case (.one, 0),
         (.many, 0...):
      break

    // Also allowed, assuming we have no leftover bytes:
    case (.one, 1):
      self.arity = .none
      // We shouldn't have any bytes leftover after reading a single message and we also should not
      // have partially read a message.
      if self.reader.unprocessedBytes != 0 || self.reader.isReading {
        return .failure(.leftOverBytes)
      }

    // Anything else must be invalid.
    default:
      return .failure(.cardinalityViolation)
    }

    return .success(messages)
  }
}
