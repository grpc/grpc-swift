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

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class GRPCServerTests: XCTestCase {
  func withInProcessClientConnectedToServer(
    services: [any RegistrableRPCService],
    interceptors: [any ServerInterceptor] = [],
    _ body: (InProcessClientTransport, GRPCServer) async throws -> Void
  ) async throws {
    let inProcess = InProcessTransport.makePair()
    let server = GRPCServer(
      transport: inProcess.server,
      services: services,
      interceptors: interceptors
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await server.run()
      }

      group.addTask {
        try await inProcess.client.connect()
      }

      try await body(inProcess.client, server)
      inProcess.client.close()
      server.stopListening()
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
        stream.outbound.finish()

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
        stream.outbound.finish()

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
        stream.outbound.finish()

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
        stream.outbound.finish()

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
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        stream.outbound.finish()

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
              stream.outbound.finish()

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
    let counter1 = ManagedAtomic(0)
    let counter2 = ManagedAtomic(0)

    try await self.withInProcessClientConnectedToServer(
      services: [BinaryEcho()],
      interceptors: [
        .requestCounter(counter1),
        .rejectAll(with: RPCError(code: .unavailable, message: "")),
        .requestCounter(counter2),
      ]
    ) { client, _ in
      try await client.withStream(
        descriptor: BinaryEcho.Methods.get,
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        stream.outbound.finish()

        let parts = try await stream.inbound.collect()
        XCTAssertStatus(parts.first) { status, _ in
          XCTAssertEqual(status.code, .unavailable)
        }
      }
    }

    XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1)
    XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 0)
  }

  func testInterceptorsAreNotAppliedToUnimplementedMethods() async throws {
    let counter = ManagedAtomic(0)

    try await self.withInProcessClientConnectedToServer(
      services: [BinaryEcho()],
      interceptors: [.requestCounter(counter)]
    ) { client, _ in
      try await client.withStream(
        descriptor: MethodDescriptor(service: "not", method: "implemented"),
        options: .defaults
      ) { stream in
        try await stream.outbound.write(.metadata([:]))
        stream.outbound.finish()

        let parts = try await stream.inbound.collect()
        XCTAssertStatus(parts.first) { status, _ in
          XCTAssertEqual(status.code, .unimplemented)
        }
      }
    }

    XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), 0)
  }

  func testNoNewRPCsAfterServerStopListening() async throws {
    try await withInProcessClientConnectedToServer(services: [BinaryEcho()]) { client, server in
      // Run an RPC so we know the server is up.
      try await self.doEchoGet(using: client)

      // New streams should fail immediately after this.
      server.stopListening()

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
        server.stopListening()

        try await stream.outbound.write(.message([0]))
        stream.outbound.finish()

        let message = try await iterator.next()
        XCTAssertMessage(message) { XCTAssertEqual($0, [0]) }
        let status = try await iterator.next()
        XCTAssertStatus(status)
      }
    }
  }

  func testCancelRunningServer() async throws {
    let inProcess = InProcessTransport.makePair()
    let task = Task {
      let server = GRPCServer(transport: inProcess.server, services: [BinaryEcho()])
      try await server.run()
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
    let server = GRPCServer(transport: InProcessServerTransport(), services: [])
    // Run the server.
    let task = Task { try await server.run() }
    task.cancel()
    try await task.value

    // Server is stopped, should throw an error.
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await server.run()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .serverIsStopped)
    }
  }

  func testRunServerWhenTransportThrows() async throws {
    let server = GRPCServer(transport: ThrowOnRunServerTransport(), services: [])
    await XCTAssertThrowsErrorAsync(ofType: RuntimeError.self) {
      try await server.run()
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
      stream.outbound.finish()
      // Don't need to validate the response, just that the server is running.
      let parts = try await stream.inbound.collect()
      XCTAssertEqual(parts.count, 3)
    }
  }
}
