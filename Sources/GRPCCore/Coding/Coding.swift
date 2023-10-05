/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

/// Serializes a message into a sequence of bytes.
///
/// Message serializers convert an input message to a sequence of bytes. Serializers are used to
/// convert messages into a form which is suitable for sending over a network. The reverse
/// operation, deserialization, is performed by a ``MessageDeserializer``.
///
/// Serializers are used frequently and implementations should take care to ensure that
/// serialization is as cheap as possible.
public protocol MessageSerializer<Message>: Sendable {
  /// The type of message this serializer can serialize.
  associatedtype Message

  /// Serializes a ``Message`` into a sequence of bytes.
  ///
  /// - Parameter message: The message to serialize.
  /// - Returns: The serialized bytes of a message.
  func serialize(_ message: Message) throws -> [UInt8]
}

/// Deserializes a sequence of bytes into a message.
///
/// Message deserializers convert a sequence of bytes into a message. Deserializers are used to
/// convert bytes received from the network into an application specific message. The reverse
/// operation, serialization, is performed by a ``MessageSerializer``.
///
/// Deserializers are used frequently and implementations should take care to ensure that
/// deserialization is as cheap as possible.
public protocol MessageDeserializer<Message>: Sendable {
  /// The type of message this deserializer can deserialize.
  associatedtype Message

  /// Deserializes a sequence of bytes into a ``Message``.
  ///
  /// - Parameter serializedMessageBytes: The bytes to deserialize.
  /// - Returns: The deserialized message.
  func deserialize(_ serializedMessageBytes: [UInt8]) throws -> Message
}
