/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOFoundationCompat
import SwiftProtobuf

public protocol MessageSerializer {
  associatedtype Input

  /// Serializes `input` into a `ByteBuffer` allocated using the provided `allocator`.
  ///
  /// - Parameters:
  ///   - input: The element to serialize.
  ///   - allocator: A `ByteBufferAllocator`.
  @inlinable
  func serialize(_ input: Input, allocator: ByteBufferAllocator) throws -> ByteBuffer
}

public protocol MessageDeserializer {
  associatedtype Output

  /// Deserializes `byteBuffer` to produce a single `Output`.
  ///
  /// - Parameter byteBuffer: The `ByteBuffer` to deserialize.
  @inlinable
  func deserialize(byteBuffer: ByteBuffer) throws -> Output
}

// MARK: Protobuf

public struct ProtobufSerializer<Message: SwiftProtobuf.Message>: MessageSerializer {
  @inlinable
  public init() {}

  @inlinable
  public func serialize(_ message: Message, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    // Serialize the message.
    let serialized = try message.serializedData()

    // Allocate enough space and an extra 5 leading bytes. This a minor optimisation win: the length
    // prefixed message writer can re-use the leading 5 bytes without needing to allocate a new
    // buffer and copy over the serialized message.
    var buffer = allocator.buffer(capacity: serialized.count + 5)
    buffer.writeRepeatingByte(0, count: 5)
    buffer.moveReaderIndex(forwardBy: 5)

    // Now write the serialized message.
    buffer.writeContiguousBytes(serialized)

    return buffer
  }
}

public struct ProtobufDeserializer<Message: SwiftProtobuf.Message>: MessageDeserializer {
  @inlinable
  public init() {}

  @inlinable
  public func deserialize(byteBuffer: ByteBuffer) throws -> Message {
    var buffer = byteBuffer
    // '!' is okay; we can always read 'readableBytes'.
    let data = buffer.readData(length: buffer.readableBytes)!
    return try Message(serializedData: data)
  }
}

// MARK: GRPCPayload

public struct GRPCPayloadSerializer<Message: GRPCPayload>: MessageSerializer {
  @inlinable
  public init() {}

  @inlinable
  public func serialize(_ message: Message, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    // Reserve 5 leading bytes. This a minor optimisation win: the length prefixed message writer
    // can re-use the leading 5 bytes without needing to allocate a new buffer and copy over the
    // serialized message.
    var buffer = allocator.buffer(repeating: 0, count: 5)

    let readerIndex = buffer.readerIndex
    let writerIndex = buffer.writerIndex

    // Serialize the payload into the buffer.
    try message.serialize(into: &buffer)

    // Ensure 'serialize(into:)' didn't do anything strange.
    assert(buffer.readerIndex == readerIndex, "serialize(into:) must not move the readerIndex")
    assert(
      buffer.writerIndex >= writerIndex,
      "serialize(into:) must not move the writerIndex backwards"
    )
    assert(
      buffer.getBytes(at: readerIndex, length: 5) == Array(repeating: 0, count: 5),
      "serialize(into:) must not write over existing written bytes"
    )

    // 'read' the first 5 bytes so that the buffer's readable bytes are only the bytes of the
    // serialized message.
    buffer.moveReaderIndex(forwardBy: 5)

    return buffer
  }
}

public struct GRPCPayloadDeserializer<Message: GRPCPayload>: MessageDeserializer {
  @inlinable
  public init() {}

  @inlinable
  public func deserialize(byteBuffer: ByteBuffer) throws -> Message {
    var buffer = byteBuffer
    return try Message(serializedByteBuffer: &buffer)
  }
}

// MARK: - Any Serializer/Deserializer

internal struct AnySerializer<Input>: MessageSerializer {
  private let _serialize: (Input, ByteBufferAllocator) throws -> ByteBuffer

  init<Serializer: MessageSerializer>(wrapping other: Serializer) where Serializer.Input == Input {
    self._serialize = other.serialize(_:allocator:)
  }

  internal func serialize(_ input: Input, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    return try self._serialize(input, allocator)
  }
}

internal struct AnyDeserializer<Output>: MessageDeserializer {
  private let _deserialize: (ByteBuffer) throws -> Output

  init<Deserializer: MessageDeserializer>(
    wrapping other: Deserializer
  ) where Deserializer.Output == Output {
    self._deserialize = other.deserialize(byteBuffer:)
  }

  internal func deserialize(byteBuffer: ByteBuffer) throws -> Output {
    return try self._deserialize(byteBuffer)
  }
}
