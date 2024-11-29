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

final class GRPCServerTests: XCTestCase {
  func withInProcessClientConnectedToServer(
    services: [any RegistrableRPCService],
    interceptorPipeline: [ServerInterceptorPipelineOperation] = [],
    _ body: (InProcessTransport.Client, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport()

    try await withGRPCServer(
      transport: inProcess.server,
      services: services,
      interceptorPipeline: interceptorPipeline
    ) { server in
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await inProcess.client.connect()
        }

        try await body(inProcess.client, server)
        inProcess.client.beginGracefulShutdown()
      }
    }
  }

  func testServerHandlesUnary() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.get,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message([3, 1, 4, 1, 5]))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        XCTAssertMetadata(metadata)

        let message = try await responseParts.next()
        XCTAssertMessage(message) {
          XCTAssertEqual($0, [3, 1, 4, 1, 5])
        }

        let status = try await responseParts.next()
        XCTAssertStatus(status) { status, _ in
          XCTAssertEqual(status.code, .ok)
        }
      }
    }
  }

  func testServerHandlesClientStreaming() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.collect,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message([3]))
        try await stream.outbound.write(.message([1]))
        try await stream.outbound.write(.message([4]))
        try await stream.outbound.write(.message([1]))
        try await stream.outbound.write(.message([5]))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        XCTAssertMetadata(metadata)

        let message = try await responseParts.next()
        XCTAssertMessage(message) {
          XCTAssertEqual($0, [3, 1, 4, 1, 5])
        }

        let status = try await responseParts.next()
        XCTAssertStatus(status) { status, _ in
          XCTAssertEqual(status.code, .ok)
        }
      }
    }
  }

  func testServerHandlesServerStreaming() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.expand,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message([3, 1, 4, 1, 5]))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        XCTAssertMetadata(metadata)

        for byte in [3, 1, 4, 1, 5] as [UInt8] {
          let message = try await responseParts.next()
          XCTAssertMessage(message) {
            XCTAssertEqual($0, [byte])
          }
        }

        let status = try await responseParts.next()
        XCTAssertStatus(status) { status, _ in
          XCTAssertEqual(status.code, .ok)
        }
      }
    }
  }

  func testServerHandlesBidirectionalStreaming() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.update,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        for byte in [3, 1, 4, 1, 5] as [UInt8] {
          try await stream.outbound.write(.message([byte]))
        }
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        XCTAssertMetadata(metadata)

        for byte in [3, 1, 4, 1, 5] as [UInt8] {
          let message = try await responseParts.next()
          XCTAssertMessage(message) {
            XCTAssertEqual($0, [byte])
          }
        }

        let status = try await responseParts.next()
        XCTAssertStatus(status) { status, _ in
          XCTAssertEqual(status.code, .ok)
        }
      }
    }
  }

  func testUnimplementedMethod() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      try await client.withStream(
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let status = try await responseParts.next()
        XCTAssertStatus(status) { status, _ in
          XCTAssertEqual(status.code, .unimplemented)
        }
      }
    }
  }

  func testMultipleConcurrentRequests() async throws {
    try await self.withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, _ in
      await withThrowingTaskGroup(of: Void.self) { group in
        for i in UInt8.min ..< UInt8.max {
          group.addTask {
            try await client.withStream(
              descriptor: BinaryEcho.Methods.get,
              options: .defaults
            ) { stream in
              try await stream.outbound.write(.metadata([:]))
              try await stream.outbound.write(.message([i]))
              await stream.outbound.finish()

              var responseParts = stream.inbound.makeAsyncIterator()
              let metadata = try await responseParts.next()
              XCTAssertMetadata(metadata)

              let message = try await responseParts.next()
              XCTAssertMessage(message) { XCTAssertEqual($0, [i]) }

              let status = try await responseParts.next()
              XCTAssertStatus(status) { status, _ in
                XCTAssertEqual(status.code, .ok)
              }
            }
          }
        }
      }
    }
  }

  func testInterceptorsAreAppliedInOrder() async throws {
    let counter1 = AtomicCounter()
    let counter2 = AtomicCounter()

    try await self.withInProcessClientConnectedToServer(
      services: [BinaryEcho()],
      interceptorPipeline: [
        .apply(.requestCounter(counter1), to: .all),
        .apply(.rejectAll(with: RPCError(code: .unavailable, message: "")), to: .all),
        .apply(.requestCounter(counter2), to: .all),
      ]
    ) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.get,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        await stream.outbound.finish()

        let parts = try await stream.inbound.collect()
        XCTAssertStatus(parts.first) { status, _ in
          XCTAssertEqual(status.code, .unavailable)
        }
      }
    }

    XCTAssertEqual(counter1.value, 1)
    XCTAssertEqual(counter2.value, 0)
  }

  func testInterceptorsAreNotAppliedToUnimplementedMethods() async throws {
    let counter = AtomicCounter()

    try await self.withInProcessClientConnectedToServer(
      services: [BinaryEcho()],
      interceptorPipeline: [.apply(.requestCounter(counter), to: .all)]
    ) { client, _ in
      try await client.withStream(
        descriptor: MethodDescriptor(fullyQualifiedService: "not", method: "implemented"),
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        await stream.outbound.finish()

        let parts = try await stream.inbound.collect()
        XCTAssertStatus(parts.first) { status, _ in
          XCTAssertEqual(status.code, .unimplemented)
        }
      }
    }

    XCTAssertEqual(counter.value, 0)
  }

  func testNoNewRPCsAfterServerStopListening() async throws {
    try await withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, server in
      // Run an RPC so we know the server is up.
      try await self.doEchoGet(using: client)

      // New streams should fail immediately after this.
      server.beginGracefulShutdown()

      // RPC should fail now.
      await XCTAssertThrowsRPCErrorAsync {
        try await client.withStream(
          descriptor: BinaryEcho.Methods.get,
          options: .defaults
        ) { stream in
          XCTFail("Stream shouldn't be opened")
        }
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
    }
  }

  func testInFlightRPCsCanContinueAfterServerStopListening() async throws {
    try await withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, server in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.update,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        var iterator = stream.inbound.makeAsyncIterator()
        // Don't need to validate the response, just that the server is running.
        let metadata = try await iterator.next()
        XCTAssertMetadata(metadata)

        // New streams should fail immediately after this.
        server.beginGracefulShutdown()

        try await stream.outbound.write(.message([0]))
        await stream.outbound.finish()

        let message = try await iterator.next()
        XCTAssertMessage(message) { XCTAssertEqual($0, [0]) }
        let status = try await iterator.next()
        XCTAssertStatus(status)
      }
    }
  }

  func testCancelRunningServer() async throws {
    let inProcess = InProcessTransport()
    let task = Task {
      let server = GRPCServer(transport: inProcess.server, services: [BinaryEcho()])
      try await server.serve()
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try? await inProcess.client.connect()
      }

      try await self.doEchoGet(using: inProcess.client)
      // The server must be running at this point as an RPC has completed.
      task.cancel()
      try await task.value

      group.cancelAll()
    }
  }

  func testTestRunStoppedServer() async throws {
    let server = GRPCServer(transport: InProcessTransport.Server(peer: "in-process"), services: [])
    // Run the server.
    let task = Task { try await server.serve() }
    task.cancel()
    try await task.value

    // Server is stopped, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await server.serve()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .serverIsStopped)
    }
  }

  func testRunServerWhenTransportThrows() async throws {
    let server = GRPCServer(transport: ThrowOnRunServerTransport(), services: [])
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await server.serve()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .transportError)
    }
  }

  private func doEchoGet(using transport: some ClientTransport) async throws {
    try await transport.withStream(
      descriptor: BinaryEcho.Methods.get,
      options: .defaults
    ) { stream in
      try await stream.outbound.write(.metadata([:]))
      try await stream.outbound.write(.message([0]))
      await stream.outbound.finish()
      // Don't need to validate the response, just that the server is running.
      let parts = try await stream.inbound.collect()
      XCTAssertEqual(parts.count, 3)
    }
  }
}

@Suite("GRPC Server Tests")
struct ServerTests {
  @Test("Interceptors are applied only to specified services")
  func testInterceptorsAreAppliedToSpecifiedServices() async throws {
    let onlyBinaryEchoCounter = AtomicCounter()
    let allServicesCounter = AtomicCounter()
    let onlyHelloWorldCounter = AtomicCounter()
    let bothServicesCounter = AtomicCounter()

    try await self.withInProcessClientConnectedToServer(
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
      try await client.withStream(
        descriptor: BinaryEcho.Methods.get,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message(Array("hello".utf8)))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        self.assertMetadata(metadata)

        let message = try await responseParts.next()
        self.assertMessage(message) {
          #expect($0 == Array("hello".utf8))
        }

        let status = try await responseParts.next()
        self.assertStatus(status) { status, _ in
          #expect(status.code == .ok, Comment(rawValue: status.description))
        }
      }

      #expect(onlyBinaryEchoCounter.value == 1)
      #expect(allServicesCounter.value == 1)
      #expect(onlyHelloWorldCounter.value == 0)
      #expect(bothServicesCounter.value == 1)

      // Now, make a request to the `HelloWorld` service and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.withStream(
        descriptor: HelloWorld.Methods.sayHello,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message(Array("Swift".utf8)))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        self.assertMetadata(metadata)

        let message = try await responseParts.next()
        self.assertMessage(message) {
          #expect($0 == Array("Hello, Swift!".utf8))
        }

        let status = try await responseParts.next()
        self.assertStatus(status) { status, _ in
          #expect(status.code == .ok, Comment(rawValue: status.description))
        }
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

    try await self.withInProcessClientConnectedToServer(
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
      try await client.withStream(
        descriptor: BinaryEcho.Methods.get,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message(Array("hello".utf8)))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        self.assertMetadata(metadata)

        let message = try await responseParts.next()
        self.assertMessage(message) {
          #expect($0 == Array("hello".utf8))
        }

        let status = try await responseParts.next()
        self.assertStatus(status) { status, _ in
          #expect(status.code == .ok, Comment(rawValue: status.description))
        }
      }

      #expect(onlyBinaryEchoGetCounter.value == 1)
      #expect(allMethodsCounter.value == 1)
      #expect(onlyBinaryEchoCollectCounter.value == 0)
      #expect(bothBinaryEchoMethodsCounter.value == 1)

      // Now, make a request to the `BinaryEcho/collect` method and assert that only
      // the counters associated to interceptors that apply to it are incremented.
      try await client.withStream(
        descriptor: BinaryEcho.Methods.collect,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        try await stream.outbound.write(.message(Array("hello".utf8)))
        await stream.outbound.finish()

        var responseParts = stream.inbound.makeAsyncIterator()
        let metadata = try await responseParts.next()
        self.assertMetadata(metadata)

        let message = try await responseParts.next()
        self.assertMessage(message) {
          #expect($0 == Array("hello".utf8))
        }

        let status = try await responseParts.next()
        self.assertStatus(status) { status, _ in
          #expect(status.code == .ok, Comment(rawValue: status.description))
        }
      }

      #expect(onlyBinaryEchoGetCounter.value == 1)
      #expect(allMethodsCounter.value == 2)
      #expect(onlyBinaryEchoCollectCounter.value == 1)
      #expect(bothBinaryEchoMethodsCounter.value == 2)
    }
  }

  func withInProcessClientConnectedToServer(
    services: [any RegistrableRPCService],
    interceptorPipeline: [ServerInterceptorPipelineOperation] = [],
    _ body: (InProcessTransport.Client, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport()
    let server = GRPCServer(
      transport: inProcess.server,
      services: services,
      interceptorPipeline: interceptorPipeline
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.serve()
      }

      group.addTask {
        try await inProcess.client.connect()
      }

      try await body(inProcess.client, server)
      inProcess.client.beginGracefulShutdown()
      server.beginGracefulShutdown()
    }
  }

  func assertMetadata(
    _ part: RPCResponsePart?,
    metadataHandler: (Metadata) -> Void = { _ in }
  ) {
    switch part {
    case .some(.metadata(let metadata)):
      metadataHandler(metadata)
    default:
      Issue.record("Expected '.metadata' but found '\(String(describing: part))'")
    }
  }

  func assertMessage(
    _ part: RPCResponsePart?,
    messageHandler: ([UInt8]) -> Void = { _ in }
  ) {
    switch part {
    case .some(.message(let message)):
      messageHandler(message)
    default:
      Issue.record("Expected '.message' but found '\(String(describing: part))'")
    }
  }

  func assertStatus(
    _ part: RPCResponsePart?,
    statusHandler: (Status, Metadata) -> Void = { _, _ in }
  ) {
    switch part {
    case .some(.status(let status, let metadata)):
      statusHandler(status, metadata)
    default:
      Issue.record("Expected '.status' but found '\(String(describing: part))'")
    }
  }
}
