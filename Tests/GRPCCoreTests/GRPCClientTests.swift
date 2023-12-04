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
import Atomics
import GRPCCore
import GRPCInProcessTransport
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class GRPCClientTests: XCTestCase {
  func makeInProcessPair() -> (client: InProcessClientTransport, server: InProcessServerTransport) {
    let server = InProcessServerTransport()
    let client = InProcessClientTransport(
      server: server,
      methodConfiguration: MethodConfigurations()
    )

    return (client, server)
  }

  func withInProcessConnectedClient(
    services: [any RegistrableRPCService],
    interceptors: [any ClientInterceptor] = [],
    _ body: (GRPCClient, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = self.makeInProcessPair()
    var configuration = GRPCClient.Configuration()
    configuration.interceptors.add(contentsOf: interceptors)
    let client = GRPCClient(transport: inProcess.client, configuration: configuration)

    let server = GRPCServer()
    server.transports.add(inProcess.server)

    for service in services {
      server.services.register(service)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run()
      }

      group.addTask {
        try await client.run()
      }

      // Make sure both server and client are running
      try await Task.sleep(for: .milliseconds(100))
      try await body(client, server)
      client.close()
      server.stopListening()
    }
  }

  struct IdentitySerializer: MessageSerializer {
    typealias Message = [UInt8]

    func serialize(_ message: [UInt8]) throws -> [UInt8] {
      return message
    }
  }

  struct IdentityDeserializer: MessageDeserializer {
    typealias Message = [UInt8]

    func deserialize(_ serializedMessageBytes: [UInt8]) throws -> [UInt8] {
      return serializedMessageBytes
    }
  }

  func testUnary() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }
    }
  }

  func testClientStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.clientStreaming(
        request: .init(producer: { writer in
          for byte in [3, 1, 4, 1, 5] as [UInt8] {
            try await writer.write([byte])
          }
        }),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }
    }
  }

  func testServerStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.serverStreaming(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.expand,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        var responseParts = response.messages.makeAsyncIterator()
        for byte in [3, 1, 4, 1, 5] as [UInt8] {
          let message = try await responseParts.next()
          XCTAssertEqual(message, [byte])
        }
      }
    }
  }

  func testBidirectionalStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.bidirectionalStreaming(
        request: .init(producer: { writer in
          for byte in [3, 1, 4, 1, 5] as [UInt8] {
            try await writer.write([byte])
          }
        }),
        descriptor: BinaryEcho.Methods.update,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        var responseParts = response.messages.makeAsyncIterator()
        for byte in [3, 1, 4, 1, 5] as [UInt8] {
          let message = try await responseParts.next()
          XCTAssertEqual(message, [byte])
        }
      }
    }
  }

  func testUnimplementedMethod_Unary() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        XCTAssertThrowsRPCError(try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testUnimplementedMethod_ClientStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.clientStreaming(
        request: .init(producer: { writer in
          for byte in [3, 1, 4, 1, 5] as [UInt8] {
            try await writer.write([byte])
          }
        }),
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        XCTAssertThrowsRPCError(try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testUnimplementedMethod_ServerStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.serverStreaming(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        XCTAssertThrowsRPCError(try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testUnimplementedMethod_BidirectionalStreaming() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      try await client.bidirectionalStreaming(
        request: .init(producer: { writer in
          for byte in [3, 1, 4, 1, 5] as [UInt8] {
            try await writer.write([byte])
          }
        }),
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        XCTAssertThrowsRPCError(try response.accepted.get()) { error in
          XCTAssertEqual(error.code, .unimplemented)
        }
      }
    }
  }

  func testMultipleConcurrentRequests() async throws {
    try await self.withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      await withThrowingTaskGroup(of: Void.self) { group in
        for i in UInt8.min ..< UInt8.max {
          group.addTask {
            try await client.unary(
              request: .init(message: [i]),
              descriptor: BinaryEcho.Methods.collect,
              serializer: IdentitySerializer(),
              deserializer: IdentityDeserializer()
            ) { response in
              let message = try response.message
              XCTAssertEqual(message, [i])
            }
          }
        }
      }
    }
  }

  func testInterceptorsAreAppliedInOrder() async throws {
    let counter1 = ManagedAtomic(0)
    let counter2 = ManagedAtomic(0)

    try await self.withInProcessConnectedClient(
      services: [BinaryEcho()],
      interceptors: [
        .requestCounter(counter1),
        .rejectAll(with: RPCError(code: .unavailable, message: "")),
        .requestCounter(counter2),
      ]
    ) { client, _ in
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        XCTAssertRejected(response) { error in
          XCTAssertEqual(error.code, .unavailable)
        }
      }
    }

    XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1)
    XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 0)
  }

  func testNoNewRPCsAfterClientClose() async throws {
    try await withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      // Run an RPC so we know the client is running properly.
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }

      // New RPCs should fail immediately after this.
      client.close()

      // RPC should fail now.
      await XCTAssertThrowsErrorAsync(ofType: ClientError.self) {
        try await client.unary(
          request: .init(message: [3, 1, 4, 1, 5]),
          descriptor: BinaryEcho.Methods.collect,
          serializer: IdentitySerializer(),
          deserializer: IdentityDeserializer()
        ) { _ in }
      } errorHandler: { error in
        XCTAssertEqual(error.code, .clientIsStopped)
      }
    }
  }

  func testInFlightRPCsCanContinueAfterClientIsClosed() async throws {
    try await withInProcessConnectedClient(services: [BinaryEcho()]) { client, server in
      try await client.clientStreaming(
        request: .init(producer: { writer in

          // Close the client once this RCP has been started.
          client.close()

          // Attempts to start a new RPC should fail.
          await XCTAssertThrowsErrorAsync(ofType: ClientError.self) {
            try await client.unary(
              request: .init(message: [3, 1, 4, 1, 5]),
              descriptor: BinaryEcho.Methods.collect,
              serializer: IdentitySerializer(),
              deserializer: IdentityDeserializer()
            ) { _ in }
          } errorHandler: { error in
            XCTAssertEqual(error.code, .clientIsStopped)
          }

          // Now write to the already opened stream to confirm that opened streams
          // can successfully run to completion.
          for byte in [3, 1, 4, 1, 5] as [UInt8] {
            try await writer.write([byte])
          }
        }),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }
    }
  }

  func testCancelRunningClient() async throws {
    let inProcess = self.makeInProcessPair()
    let client = GRPCClient(transport: inProcess.client)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        let server = GRPCServer()
        server.services.register(BinaryEcho())
        server.transports.add(inProcess.server)
        try await server.run()
      }

      group.addTask {
        try await client.run()
      }

      // Wait for client and server to be running.
      try await Task.sleep(for: .milliseconds(10))

      let task = Task {
        try await client.clientStreaming(
          request: .init(producer: { writer in
            try await Task.sleep(for: .seconds(5))
          }),
          descriptor: BinaryEcho.Methods.collect,
          serializer: IdentitySerializer(),
          deserializer: IdentityDeserializer()
        ) { response in
          XCTAssertRejected(response) { error in
            XCTAssertEqual(error.code, .unknown)
          }
        }
      }

      // Check requests are getting through.
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }

      task.cancel()
      try await task.value
      group.cancelAll()
    }
  }

  func testRunStoppedClient() async throws {
    let (clientTransport, _) = self.makeInProcessPair()
    let client = GRPCClient(transport: clientTransport)
    // Run the client.
    let task = Task { try await client.run() }
    task.cancel()
    try await task.value

    // Client is stopped, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: ClientError.self) {
      try await client.run()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .clientIsStopped)
    }
  }

  func testRunAlreadyRunningClient() async throws {
    let (clientTransport, _) = self.makeInProcessPair()
    let client = GRPCClient(transport: clientTransport)
    // Run the client.
    let task = Task { try await client.run() }
    // Make sure the client is run for the first time here.
    try await Task.sleep(for: .milliseconds(10))

    // Client is already running, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: ClientError.self) {
      try await client.run()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .clientIsAlreadyRunning)
    }

    task.cancel()
  }

  func testRunClientNotRunning() async throws {
    let (clientTransport, _) = self.makeInProcessPair()
    let client = GRPCClient(transport: clientTransport)

    // Client is not running, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: ClientError.self) {
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer()
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }
    } errorHandler: { error in
      XCTAssertEqual(error.code, .clientIsNotRunning)
    }
  }

  func testInterceptorsDescription() async throws {
    var config = GRPCClient.Configuration()
    config.interceptors.add(.rejectAll(with: .init(code: .aborted, message: "")))
    config.interceptors.add(.requestCounter(.init(0)))

    let description = String(describing: config.interceptors)
    let expected = #"["RejectAllClientInterceptor", "RequestCountingClientInterceptor"]"#
    XCTAssertEqual(description, expected)
  }
}
