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
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf

struct Greet: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Sends a request to the greeter server")

  @Option(help: "The port to listen on")
  var port: Int = 31415

  @Option(help: "The person to greet")
  var name: String = ""

  func run() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      let client = GRPCClient(
        transport: try .http2NIOPosix(
          target: .ipv4(host: "127.0.0.1", port: self.port),
          config: .defaults(transportSecurity: .plaintext)
        )
      )

      group.addTask {
        try await client.run()
      }

      defer {
        client.beginGracefulShutdown()
      }

      let greeter = Helloworld_Greeter_Client(wrapping: client)
      let reply = try await greeter.sayHello(.with { $0.name = self.name })
      print(reply.message)
    }
  }
}
