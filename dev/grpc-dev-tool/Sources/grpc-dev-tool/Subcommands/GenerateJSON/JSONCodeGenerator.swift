/*
 * Copyright 2025, gRPC Authors All rights reserved.
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
import GRPCCodeGen

struct JSONCodeGenerator {
  private static let currentYear: Int = {
    let now = Date()
    let year = Calendar.current.component(.year, from: Date())
    return year
  }()

  private static let header = """
    /*
     * Copyright \(Self.currentYear), gRPC Authors All rights reserved.
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
    """

  private static let jsonSerializers: String = """
    fileprivate struct JSONSerializer<Message: Codable>: MessageSerializer {
      fileprivate func serialize<Bytes: GRPCContiguousBytes>(
        _ message: Message
      ) throws -> Bytes {
        do {
          let jsonEncoder = JSONEncoder()
          let data = try jsonEncoder.encode(message)
          return Bytes(data)
        } catch {
          throw RPCError(
            code: .internalError,
            message: "Can't serialize message to JSON.",
            cause: error
          )
        }
      }
    }

    fileprivate struct JSONDeserializer<Message: Codable>: MessageDeserializer {
      fileprivate func deserialize<Bytes: GRPCContiguousBytes>(
        _ serializedMessageBytes: Bytes
      ) throws -> Message {
        do {
          let jsonDecoder = JSONDecoder()
          let data = serializedMessageBytes.withUnsafeBytes { Data($0) }
          return try jsonDecoder.decode(Message.self, from: data)
        } catch {
          throw RPCError(
            code: .internalError,
            message: "Can't deserialize message from JSON.",
            cause: error
          )
        }
      }
    }
    """

  func generate(request: JSONCodeGeneratorRequest) throws -> SourceFile {
    let generator = SourceGenerator(config: SourceGenerator.Config(request.config))

    let codeGenRequest = CodeGenerationRequest(
      fileName: request.service.name + ".swift",
      leadingTrivia: Self.header,
      dependencies: [
        Dependency(
          item: Dependency.Item(kind: .struct, name: "Data"),
          module: "Foundation",
          accessLevel: .internal
        ),
        Dependency(
          item: Dependency.Item(kind: .class, name: "JSONEncoder"),
          module: "Foundation",
          accessLevel: .internal
        ),
        Dependency(
          item: Dependency.Item(kind: .class, name: "JSONDecoder"),
          module: "Foundation",
          accessLevel: .internal
        ),
      ],
      services: [ServiceDescriptor(request.service)],
      lookupSerializer: { type in "JSONSerializer<\(type)>()" },
      lookupDeserializer: { type in "JSONDeserializer<\(type)>()" }
    )

    var sourceFile = try generator.generate(codeGenRequest)

    // Insert a fileprivate serializer/deserializer for JSON at the bottom of each file.
    sourceFile.contents += "\n\n"
    sourceFile.contents += Self.jsonSerializers

    return sourceFile
  }
}
