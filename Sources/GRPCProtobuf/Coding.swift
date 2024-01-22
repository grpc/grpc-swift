/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import GRPCCore
import SwiftProtobuf

/// Serializes a Protobuf message into a sequence of bytes.
public struct ProtobufSerializer<Message: SwiftProtobuf.Message>: GRPCCore.MessageSerializer {
  public init() {}

  /// Serializes a ``Message`` into a sequence of bytes.
  ///
  /// - Parameter message: The message to serialize.
  /// - Returns: An array of serialized bytes representing the message.
  public func serialize(_ message: Message) throws -> [UInt8] {
    do {
      let data = try message.serializedData()
      return Array(data)
    } catch let error {
      throw RPCError(
        code: .invalidArgument,
        message: "Can't serialize message of type \(type(of: message)).",
        cause: error
      )
    }
  }
}

/// Deserializes a sequence of bytes into a Protobuf message.
public struct ProtobufDeserializer<Message: SwiftProtobuf.Message>: GRPCCore.MessageDeserializer {
  public init() {}

  /// Deserializes a sequence of bytes into a ``Message``.
  ///
  /// - Parameter serializedMessageBytes: The array of bytes to deserialize.
  /// - Returns: The deserialized message.
  public func deserialize(_ serializedMessageBytes: [UInt8]) throws -> Message {
    do {
      let message = try Message(contiguousBytes: serializedMessageBytes)
      return message
    } catch let error {
      throw RPCError(
        code: .invalidArgument,
        message: "Can't deserialize to message of type \(Message.self)",
        cause: error
      )
    }
  }
}
