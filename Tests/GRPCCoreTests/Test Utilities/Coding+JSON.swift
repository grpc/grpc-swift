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
import GRPCCore

import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

struct JSONSerializer<Message: Codable>: MessageSerializer {
  func serialize<Bytes: GRPCContiguousBytes>(_ message: Message) throws -> Bytes {
    do {
      let jsonEncoder = JSONEncoder()
      let data = try jsonEncoder.encode(message)
      return Bytes(data)
    } catch {
      throw RPCError(code: .internalError, message: "Can't serialize message to JSON. \(error)")
    }
  }
}

struct JSONDeserializer<Message: Codable>: MessageDeserializer {
  func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> Message {
    do {
      let jsonDecoder = JSONDecoder()
      let data = serializedMessageBytes.withUnsafeBytes { Data($0) }
      return try jsonDecoder.decode(Message.self, from: data)
    } catch {
      throw RPCError(code: .internalError, message: "Can't deserialze message from JSON. \(error)")
    }
  }
}
