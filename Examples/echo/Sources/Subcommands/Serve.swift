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

struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Starts an echo server.")

  @Option(help: "The port to listen on")
  var port: Int = 1234

  func run() async throws {
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: self.port),
        transportSecurity: .plaintext
      ),
      services: [EchoService()]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask { try await server.serve() }
      if let address = try await server.listeningAddress {
        print("Echo listening on \(address)")
      }
    }
  }
}

struct EchoService: Echo_Echo.SimpleServiceProtocol {
  func get(
    request: Echo_EchoRequest,
    context: ServerContext
  ) async throws -> Echo_EchoResponse {
    return .with { $0.text = request.text }
  }

  func collect(
    request: RPCAsyncSequence<Echo_EchoRequest, any Error>,
    context: ServerContext
  ) async throws -> Echo_EchoResponse {
    let messages = try await request.reduce(into: []) { $0.append($1.text) }
    let joined = messages.joined(separator: " ")
    return .with { $0.text = joined }
  }

  func expand(
    request: Echo_EchoRequest,
    response: RPCWriter<Echo_EchoResponse>,
    context: ServerContext
  ) async throws {
    let parts = request.text.split(separator: " ")
    let messages = parts.map { part in Echo_EchoResponse.with { $0.text = String(part) } }
    try await response.write(contentsOf: messages)
  }

  func update(
    request: RPCAsyncSequence<Echo_EchoRequest, any Error>,
    response: RPCWriter<Echo_EchoResponse>,
    context: ServerContext
  ) async throws {
    for try await message in request {
      try await response.write(.with { $0.text = message.text })
    }
  }
}
