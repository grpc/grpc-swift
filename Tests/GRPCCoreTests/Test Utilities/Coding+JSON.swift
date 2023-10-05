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

private let jsonEncoder = JSONEncoder()
private let jsonDecoder = JSONDecoder()

struct JSONSerializer<Message: Codable>: MessageSerializer {
  func serialize(_ message: Message) throws -> [UInt8] {
    do {
      return try Array(jsonEncoder.encode(message))
    } catch {
      throw RPCError(code: .internalError, message: "Can't serialize message to JSON. \(error)")
    }
  }
}

struct JSONDeserializer<Message: Codable>: MessageDeserializer {
  func deserialize(_ serializedMessageBytes: [UInt8]) throws -> Message {
    do {
      return try jsonDecoder.decode(Message.self, from: Data(serializedMessageBytes))
    } catch {
      throw RPCError(code: .internalError, message: "Can't deserialze message from JSON. \(error)")
    }
  }
}
