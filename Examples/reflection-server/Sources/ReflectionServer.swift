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

import ArgumentParser
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import GRPCReflectionService

@main
struct ReflectionServer: AsyncParsableCommand {
  @Option(help: "The port to listen on")
  var port: Int = 31415

  func run() async throws {
    // Find descriptor sets ('*.pb') bundled with this example.
    let paths = Bundle.module.paths(forResourcesOfType: "pb", inDirectory: "DescriptorSets")

    // Start the server with the reflection service and the echo service.
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: self.port),
        transportSecurity: .plaintext
      ),
      services: [
        try ReflectionService(descriptorSetFilePaths: paths),
        EchoService(),
      ]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.serve() }
      if let address = try await server.listeningAddress?.ipv4 {
        print("Reflection server listening on \(address)")
        print(String(repeating: "-", count: 80))

        let example = """
          If you have grpcurl installed you can query the service to discover services
          and make calls against them. You can install grpcurl by following the
          instruction in its repository: https://github.com/fullstorydev/grpcurl

          Here are some example commands:

            List all services:
              $ grpcurl -plaintext \(address.host):\(address.port) list

            Describe the 'Get' method in the 'echo.Echo' service:
              $ grpcurl -plaintext \(address.host):\(address.port) describe echo.Echo.Get

            Call the 'echo.Echo.Get' method:
              $ grpcurl -plaintext -d '{ "text": "Hello" }' \(address.host):\(address.port) echo.Echo.Get
          """
        print(example)
      }
    }
  }
}
