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
struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Starts a greeter server.")

  @Option(help: "The port to listen on")
  var port: Int = 31415

  func run() async throws {
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: self.port),
        config: .defaults(transportSecurity: .plaintext)
      ),
      services: [Greeter()]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.serve() }
      if let address = try await server.listeningAddress {
        print("Greeter listening on \(address)")
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
struct Greeter: Helloworld_GreeterServiceProtocol {
  func sayHello(
    request: ServerRequest.Single<Helloworld_HelloRequest>
  ) async throws -> ServerResponse.Single<Helloworld_HelloReply> {
    var reply = Helloworld_HelloReply()
    let recipient = request.message.name.isEmpty ? "stranger" : request.message.name
    reply.message = "Hello, \(recipient)"
    return ServerResponse.Single(message: reply)
  }
}
