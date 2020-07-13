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
import NIO
import NIOFoundationCompat
import SwiftProtobuf

internal protocol MessageSerializer {
  associatedtype Input

  /// Serializes `input` into a `ByteBuffer` allocated using the provided `allocator`.
  ///
  /// The serialized buffer should have 5 leading bytes: the first must be zero, the following
  /// four bytes are the `UInt32` encoded length of the serialized message. The bytes of the
  /// serialized message follow.
  ///
  /// - Parameters:
  ///   - input: The element to serialize.
  ///   - allocator: A `ByteBufferAllocator`.
  func serialize(_ input: Input, allocator: ByteBufferAllocator) throws -> ByteBuffer
}

internal protocol MessageDeserializer {
  associatedtype Output

  /// Deserializes `byteBuffer` to produce a single `Output`.
  ///
  /// - Parameter byteBuffer: The `ByteBuffer` to deserialize.
  func deserialize(byteBuffer: ByteBuffer) throws -> Output
}

// MARK: Protobuf

internal struct ProtobufSerializer<Message: SwiftProtobuf.Message>: MessageSerializer {
  internal func serialize(_ message: Message, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    // Serialize the message.
    let serialized = try message.serializedData()

    var buffer = allocator.buffer(capacity: serialized.count + 5)

    // The compression byte. This will be modified later, if necessary.
    buffer.writeInteger(UInt8(0))

    // The length of the serialized message.
    buffer.writeInteger(UInt32(serialized.count))

    // The serialized message.
    buffer.writeBytes(serialized)

    return buffer
  }
}

internal struct ProtobufDeserializer<Message: SwiftProtobuf.Message>: MessageDeserializer {
  internal func deserialize(byteBuffer: ByteBuffer) throws -> Message {
    var buffer = byteBuffer
    // '!' is okay; we can always read 'readableBytes'.
    let data = buffer.readData(length: buffer.readableBytes)!
    return try Message(serializedData: data)
  }
}

// MARK: GRPCPayload

internal struct GRPCPayloadSerializer<Message: GRPCPayload>: MessageSerializer {
  internal func serialize(_ message: Message, allocator: ByteBufferAllocator) throws -> ByteBuffer {
    // Reserve 5 leading bytes.
    var buffer = allocator.buffer(repeating: 0, count: 5)

    let readerIndex = buffer.readerIndex
    let writerIndex = buffer.writerIndex

    // Serialize the payload into the buffer.
    try message.serialize(into: &buffer)

    // Ensure 'serialize(into:)' didn't do anything strange.
    assert(buffer.readerIndex == readerIndex, "serialize(into:) must not move the readerIndex")
    assert(buffer.writerIndex >= writerIndex, "serialize(into:) must not move the writerIndex backwards")
    assert(buffer.getBytes(at: readerIndex, length: 5) == Array(repeating: 0, count: 5),
           "serialize(into:) must not write over existing written bytes")

    // The first byte is already zero. Set the length.
    let messageSize = buffer.writerIndex - writerIndex
    buffer.setInteger(UInt32(messageSize), at: readerIndex + 1)

    return buffer
  }
}

internal struct GRPCPayloadDeserializer<Message: GRPCPayload>: MessageDeserializer {
  internal func deserialize(byteBuffer: ByteBuffer) throws -> Message {
    var buffer = byteBuffer
    return try Message(serializedByteBuffer: &buffer)
  }
}

