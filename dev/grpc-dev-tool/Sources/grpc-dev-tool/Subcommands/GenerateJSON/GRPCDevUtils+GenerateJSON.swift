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

import ArgumentParser
import Foundation

struct GenerateJSON: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "generate-json",
    subcommands: [Generate.self, DumpConfig.self],
    defaultSubcommand: Generate.self
  )
}

extension GenerateJSON {
  struct Generate: ParsableCommand {
    @Argument(help: "The path to a JSON input file.")
    var input: String

    func run() throws {
      // Decode the input file.
      let url = URL(filePath: self.input)
      let data = try Data(contentsOf: url)
      let json = JSONDecoder()
      let config = try json.decode(JSONCodeGeneratorRequest.self, from: data)

      // Generate the output and dump it to stdout.
      let generator = JSONCodeGenerator()
      let sourceFile = try generator.generate(request: config)
      print(sourceFile.contents)
    }
  }
}

extension GenerateJSON {
  struct DumpConfig: ParsableCommand {
    func run() throws {
      // Create a request for the code generator using all four RPC kinds.
      var request = JSONCodeGeneratorRequest(
        service: ServiceSchema(name: "Echo", methods: []),
        config: .defaults
      )

      let methodNames = ["get", "collect", "expand", "update"]
      let methodKinds: [ServiceSchema.Method.Kind] = [
        .unary,
        .clientStreaming,
        .serverStreaming,
        .bidiStreaming,
      ]

      for (name, kind) in zip(methodNames, methodKinds) {
        let method = ServiceSchema.Method(
          name: name,
          input: "EchoRequest",
          output: "EchoResponse",
          kind: kind
        )
        request.service.methods.append(method)
      }

      // Encoding the config to JSON and dump it to stdout.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted]
      let data = try encoder.encode(request)
      let json = String(decoding: data, as: UTF8.self)
      print(json)
    }
  }
}
