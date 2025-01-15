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
import XCTest

final class InProcessClientTransportTests: XCTestCase {
  struct FailTest: Error {}

  func testConnectWhenConnected() async {
    let client = makeClient()

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect()
      }

      group.addTask {
        try await client.connect()
      }

      await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
        try await group.next()
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
      group.cancelAll()
    }
  }

  func testConnectWhenClosed() async {
    let client = makeClient()

    client.beginGracefulShutdown()

    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      try await client.connect()
    } errorHandler: { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testConnectWhenClosedAfterCancellation() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect()
      }
      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
      }

      try await group.next()
      group.cancelAll()

      await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
        try await client.connect()
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
    }
  }

  func testCloseWhenUnconnected() {
    let client = makeClient()

    XCTAssertNoThrow(client.beginGracefulShutdown())
  }

  func testCloseWhenClosed() {
    let client = makeClient()
    client.beginGracefulShutdown()

    XCTAssertNoThrow(client.beginGracefulShutdown())
  }

  func testConnectSuccessfullyAndThenClose() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect()
      }
      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
      }

      try await group.next()
      client.beginGracefulShutdown()
    }
  }

  func testOpenStreamWhenUnconnected() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.withStream(descriptor: .testTest, options: .defaults) { _, _ in
          // Once the pending stream is opened, close the client to new connections,
          // so that, once this closure is executed and this stream is closed,
          // the client will return from `connect()`.
          client.beginGracefulShutdown()
        }
      }

      group.addTask {
        // Add a sleep to make sure connection happens after `withStream` has been called,
        // to test pending streams are handled correctly.
        try await Task.sleep(for: .milliseconds(100))
        try await client.connect()
      }

      try await group.waitForAll()
    }
  }

  func testOpenStreamWhenClosed() async {
    let client = makeClient()

    client.beginGracefulShutdown()

    await XCTAssertThrowsErrorAsync(ofType: RPCError.self) {
      try await client.withStream(descriptor: .testTest, options: .defaults) { _, _ in }
    } errorHandler: { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testOpenStreamSuccessfullyAndThenClose() async throws {
    let server = InProcessTransport.Server(peer: "in-process:1234")
    let client = makeClient(server: server)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect()
      }

      group.addTask {
        try await client.withStream(descriptor: .testTest, options: .defaults) { stream, _ in
          try await stream.outbound.write(.message([1]))
          await stream.outbound.finish()
          let receivedMessages = try await stream.inbound.reduce(into: []) { $0.append($1) }

          XCTAssertEqual(receivedMessages, [.message([42])])
        }
      }

      group.addTask {
        try await server.listen { stream, context in
          let receivedMessages = try? await stream.inbound.reduce(into: []) { $0.append($1) }
          try? await stream.outbound.write(RPCResponsePart.message([42]))
          await stream.outbound.finish()

          XCTAssertEqual(receivedMessages, [.message([1])])
        }
      }

      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
        client.beginGracefulShutdown()
      }

      try await group.next()
      group.cancelAll()
    }
  }

  func testExecutionConfiguration() {
    let policy = HedgingPolicy(
      maxAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )

    var serviceConfig = ServiceConfig(
      methodConfig: [
        MethodConfig(
          names: [
            MethodConfig.Name(service: "", method: "")
          ],
          executionPolicy: .hedge(policy)
        )
      ]
    )

    var client = InProcessTransport.Client(
      server: InProcessTransport.Server(peer: "in-process:1234"),
      serviceConfig: serviceConfig
    )

    let firstDescriptor = MethodDescriptor(fullyQualifiedService: "test", method: "first")
    XCTAssertEqual(
      client.config(forMethod: firstDescriptor),
      serviceConfig.methodConfig.first
    )

    let retryPolicy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )

    let overrideConfiguration = MethodConfig(
      names: [MethodConfig.Name(service: "test", method: "second")],
      executionPolicy: .retry(retryPolicy)
    )
    serviceConfig.methodConfig.append(overrideConfiguration)
    client = InProcessTransport.Client(
      server: InProcessTransport.Server(peer: "in-process:1234"),
      serviceConfig: serviceConfig
    )

    let secondDescriptor = MethodDescriptor(fullyQualifiedService: "test", method: "second")
    XCTAssertEqual(
      client.config(forMethod: firstDescriptor),
      serviceConfig.methodConfig.first
    )
    XCTAssertEqual(
      client.config(forMethod: secondDescriptor),
      serviceConfig.methodConfig.last
    )
  }

  func testOpenMultipleStreamsThenClose() async throws {
    let server = InProcessTransport.Server(peer: "in-process:1234")
    let client = makeClient(server: server)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect()
      }

      group.addTask {
        try await client.withStream(descriptor: .testTest, options: .defaults) { stream, _ in
          try await Task.sleep(for: .milliseconds(100))
        }
      }

      group.addTask {
        try await client.withStream(descriptor: .testTest, options: .defaults) { stream, _ in
          try await Task.sleep(for: .milliseconds(100))
        }
      }

      group.addTask {
        try await Task.sleep(for: .milliseconds(50))
        client.beginGracefulShutdown()
      }

      try await group.next()
    }
  }

  func makeClient(
    server: InProcessTransport.Server = InProcessTransport.Server(peer: "in-process:1234")
  ) -> InProcessTransport.Client {
    let defaultPolicy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )

    let serviceConfig = ServiceConfig(
      methodConfig: [
        MethodConfig(
          names: [MethodConfig.Name(service: "", method: "")],
          executionPolicy: .retry(defaultPolicy)
        )
      ]
    )

    return InProcessTransport.Client(
      server: server,
      serviceConfig: serviceConfig
    )
  }
}

extension MethodDescriptor {
  static let testTest = Self(fullyQualifiedService: "test", method: "test")
}
