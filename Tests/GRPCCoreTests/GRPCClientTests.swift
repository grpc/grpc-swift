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
import GRPCInProcessTransport
import Testing
import XCTest

final class GRPCClientTests: XCTestCase {
  func withInProcessConnectedClient(
    services: [any RegistrableRPCService],
    interceptorPipeline: [ClientInterceptorPipelineOperation] = [],
    _ body: (GRPCClient, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport()
    _ = GRPCClient(transport: inProcess.client, interceptorPipeline: interceptorPipeline)
    _ = GRPCServer(transport: inProcess.server, services: services)

    try await withGRPCServer(
      transport: inProcess.server,
      services: services
    ) { server in
      try await withGRPCClient(
        transport: inProcess.client,
        interceptorPipeline: interceptorPipeline
      ) { client in
        try await Task.sleep(for: .milliseconds(100))
        try await body(client, server)
      }
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
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
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
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
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
              deserializer: IdentityDeserializer(),
              options: .defaults
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
    let counter1 = AtomicCounter()
    let counter2 = AtomicCounter()

    try await self.withInProcessConnectedClient(
      services: [BinaryEcho()],
      interceptorPipeline: [
        .apply(.requestCounter(counter1), to: .all),
        .apply(.rejectAll(with: RPCError(code: .unavailable, message: "")), to: .all),
        .apply(.requestCounter(counter2), to: .all),
      ]
    ) { client, _ in
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        XCTAssertRejected(response) { error in
          XCTAssertEqual(error.code, .unavailable)
        }
      }
    }

    XCTAssertEqual(counter1.value, 1)
    XCTAssertEqual(counter2.value, 0)
  }

  func testNoNewRPCsAfterClientClose() async throws {
    try await withInProcessConnectedClient(services: [BinaryEcho()]) { client, _ in
      // Run an RPC so we know the client is running properly.
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }

      // New RPCs should fail immediately after this.
      client.beginGracefulShutdown()

      // RPC should fail now.
      await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
        try await client.unary(
          request: .init(message: [3, 1, 4, 1, 5]),
          descriptor: BinaryEcho.Methods.collect,
          serializer: IdentitySerializer(),
          deserializer: IdentityDeserializer(),
          options: .defaults
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
          client.beginGracefulShutdown()

          // Attempts to start a new RPC should fail.
          await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
            try await client.unary(
              request: .init(message: [3, 1, 4, 1, 5]),
              descriptor: BinaryEcho.Methods.collect,
              serializer: IdentitySerializer(),
              deserializer: IdentityDeserializer(),
              options: .defaults
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
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }
    }
  }

  func testCancelRunningClient() async throws {
    let inProcess = InProcessTransport()
    let client = GRPCClient(transport: inProcess.client)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        let server = GRPCServer(transport: inProcess.server, services: [BinaryEcho()])
        try await server.serve()
      }

      group.addTask {
        try await client.runConnections()
      }

      // Wait for client and server to be running.
      try await client.unary(
        request: .init(message: [3, 1, 4, 1, 5]),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try response.message
        XCTAssertEqual(message, [3, 1, 4, 1, 5])
      }

      let task = Task {
        try await client.clientStreaming(
          request: StreamingClientRequest { writer in
            try await Task.sleep(for: .seconds(5))
          },
          descriptor: BinaryEcho.Methods.collect,
          serializer: IdentitySerializer(),
          deserializer: IdentityDeserializer(),
          options: .defaults
        ) { response in
          XCTAssertRejected(response) { error in
            XCTAssertEqual(error.code, .unknown)
          }
        }
      }

      task.cancel()
      try await task.value
      group.cancelAll()
    }
  }

  func testRunStoppedClient() async throws {
    let inProcess = InProcessTransport()
    let client = GRPCClient(transport: inProcess.client)
    // Run the client.
    let task = Task { try await client.runConnections() }
    task.cancel()
    try await task.value

    // Client is stopped, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await client.runConnections()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .clientIsStopped)
    }
  }

  func testRunAlreadyRunningClient() async throws {
    let inProcess = InProcessTransport()
    let client = GRPCClient(transport: inProcess.client)
    // Run the client.
    let task = Task { try await client.runConnections() }
    // Make sure the client is run for the first time here.
    try await Task.sleep(for: .milliseconds(10))

    // Client is already running, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await client.runConnections()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .clientIsAlreadyRunning)
    }

    task.cancel()
  }
}

@Suite("GRPC Client Tests")
struct ClientTests {
  @Test("Interceptors are applied only to specified services")
  func testInterceptorsAreAppliedToSpecifiedServices() async throws {
    let onlyBinaryEchoCounter = AtomicCounter()
    let allServicesCounter = AtomicCounter()
    let onlyHelloWorldCounter = AtomicCounter()
    let bothServicesCounter = AtomicCounter()

    try await self.withInProcessConnectedClient(
      services: [BinaryEcho(), HelloWorld()],
      interceptorPipeline: [
        .apply(
          .requestCounter(onlyBinaryEchoCounter),
          to: .services([BinaryEcho.serviceDescriptor])
        ),
        .apply(.requestCounter(allServicesCounter), to: .all),
        .apply(
          .requestCounter(onlyHelloWorldCounter),
          to: .services([HelloWorld.serviceDescriptor])
        ),
        .apply(
          .requestCounter(bothServicesCounter),
          to: .services([BinaryEcho.serviceDescriptor, HelloWorld.serviceDescriptor])
        ),
      ]
    ) { client, _ in
      // Make a request to the `BinaryEcho` service and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.unary(
        request: .init(message: Array("hello".utf8)),
        descriptor: BinaryEcho.Methods.get,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try #require(try response.message)
        #expect(message == Array("hello".utf8))
      }

      #expect(onlyBinaryEchoCounter.value == 1)
      #expect(allServicesCounter.value == 1)
      #expect(onlyHelloWorldCounter.value == 0)
      #expect(bothServicesCounter.value == 1)

      // Now, make a request to the `HelloWorld` service and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.unary(
        request: .init(message: Array("Swift".utf8)),
        descriptor: HelloWorld.Methods.sayHello,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try #require(try response.message)
        #expect(message == Array("Hello, Swift!".utf8))
      }

      #expect(onlyBinaryEchoCounter.value == 1)
      #expect(allServicesCounter.value == 2)
      #expect(onlyHelloWorldCounter.value == 1)
      #expect(bothServicesCounter.value == 2)
    }
  }

  @Test("Interceptors are applied only to specified methods")
  func testInterceptorsAreAppliedToSpecifiedMethods() async throws {
    let onlyBinaryEchoGetCounter = AtomicCounter()
    let onlyBinaryEchoCollectCounter = AtomicCounter()
    let bothBinaryEchoMethodsCounter = AtomicCounter()
    let allMethodsCounter = AtomicCounter()

    try await self.withInProcessConnectedClient(
      services: [BinaryEcho()],
      interceptorPipeline: [
        .apply(
          .requestCounter(onlyBinaryEchoGetCounter),
          to: .methods([BinaryEcho.Methods.get])
        ),
        .apply(.requestCounter(allMethodsCounter), to: .all),
        .apply(
          .requestCounter(onlyBinaryEchoCollectCounter),
          to: .methods([BinaryEcho.Methods.collect])
        ),
        .apply(
          .requestCounter(bothBinaryEchoMethodsCounter),
          to: .methods([BinaryEcho.Methods.get, BinaryEcho.Methods.collect])
        ),
      ]
    ) { client, _ in
      // Make a request to the `BinaryEcho/get` method and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.unary(
        request: .init(message: Array("hello".utf8)),
        descriptor: BinaryEcho.Methods.get,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try #require(try response.message)
        #expect(message == Array("hello".utf8))
      }

      #expect(onlyBinaryEchoGetCounter.value == 1)
      #expect(allMethodsCounter.value == 1)
      #expect(onlyBinaryEchoCollectCounter.value == 0)
      #expect(bothBinaryEchoMethodsCounter.value == 1)

      // Now, make a request to the `BinaryEcho/collect` method and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.unary(
        request: .init(message: Array("hello".utf8)),
        descriptor: BinaryEcho.Methods.collect,
        serializer: IdentitySerializer(),
        deserializer: IdentityDeserializer(),
        options: .defaults
      ) { response in
        let message = try #require(try response.message)
        #expect(message == Array("hello".utf8))
      }

      #expect(onlyBinaryEchoGetCounter.value == 1)
      #expect(allMethodsCounter.value == 2)
      #expect(onlyBinaryEchoCollectCounter.value == 1)
      #expect(bothBinaryEchoMethodsCounter.value == 2)
    }
  }

  func withInProcessConnectedClient(
    services: [any RegistrableRPCService],
    interceptorPipeline: [ClientInterceptorPipelineOperation] = [],
    _ body: (GRPCClient, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport()
    let client = GRPCClient(transport: inProcess.client, interceptorPipeline: interceptorPipeline)
    let server = GRPCServer(transport: inProcess.server, services: services)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.serve()
      }

      group.addTask {
        try await client.runConnections()
      }

      // Make sure both server and client are running
      try await Task.sleep(for: .milliseconds(100))
      try await body(client, server)
      client.beginGracefulShutdown()
      server.beginGracefulShutdown()
    }
  }
}
