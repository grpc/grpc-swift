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
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOPosix

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Starts an echo server.")

  @Option(help: "The port to listen on")
  var port: Int = 1234

  func run() async throws {
    let transport = HTTP2ServerTransport.Posix(address: .ipv4(host: "127.0.0.1", port: self.port))
    let server = GRPCServer(transport: transport, services: [EchoService()])
    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.run() }
      let address = try await transport.listeningAddress
      print("server listening on \(address)")
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct EchoService: Echo_EchoServiceProtocol {
  func get(
    request: ServerRequest.Single<Echo_EchoRequest>
  ) async throws -> ServerResponse.Single<Echo_EchoResponse> {
    return ServerResponse.Single(message: .with { $0.text = request.message.text })
  }

  func collect(
    request: ServerRequest.Stream<Echo_EchoRequest>
  ) async throws -> ServerResponse.Single<Echo_EchoResponse> {
    let messages = try await request.messages.reduce(into: []) { $0.append($1.text) }
    let joined = messages.joined(separator: " ")
    return ServerResponse.Single(message: .with { $0.text = joined })
  }

  func expand(
    request: ServerRequest.Single<Echo_EchoRequest>
  ) async throws -> ServerResponse.Stream<Echo_EchoResponse> {
    return ServerResponse.Stream { writer in
      let parts = request.message.text.split(separator: " ")
      let messages = parts.map { part in Echo_EchoResponse.with { $0.text = String(part) } }
      try await writer.write(contentsOf: messages)
      return [:]
    }
  }

  func update(
    request: ServerRequest.Stream<Echo_EchoRequest>
  ) async throws -> ServerResponse.Stream<Echo_EchoResponse> {
    return ServerResponse.Stream { writer in
      for try await message in request.messages {
        try await writer.write(.with { $0.text = message.text })
      }
      return [:]
    }
  }
}
