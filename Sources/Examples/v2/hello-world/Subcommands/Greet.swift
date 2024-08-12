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

internal import ArgumentParser
internal import GRPCHTTP2Transport
internal import GRPCProtobuf

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Greet: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Sends a request to the greeter server")

  @Option(help: "The port to listen on")
  var port: Int = 31415

  @Option(help: "The person to greet")
  var name: String = ""

  func run() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      let http2 = try HTTP2ClientTransport.Posix(target: .ipv4(host: "127.0.0.1", port: self.port))
      let client = GRPCClient(transport: http2)

      group.addTask {
        try await client.run()
      }

      defer {
        client.close()
      }

      let greeter = Helloworld_GreeterClient(wrapping: client)
      let reply = try await greeter.sayHello(.with { $0.name = self.name })
      print(reply.message)
    }
  }
}
