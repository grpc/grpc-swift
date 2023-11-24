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

import XCTest

@testable import GRPCCore

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class InProcessClientTransportTests: XCTestCase {
  struct FailTest: Error {}

  func testConnectWhenConnected() async {
    let client = makeClient()

    await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }

      group.addTask {
        try await client.connect(lazily: false)
      }

      await XCTAssertThrowsRPCErrorAsync {
        try await group.next()
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
      group.cancelAll()
    }
  }

  func testConnectWhenClosed() async {
    let client = makeClient()

    client.close()

    await XCTAssertThrowsRPCErrorAsync {
      try await client.connect(lazily: false)
    } errorHandler: { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testConnectWhenClosedAfterCancellation() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }
      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
      }

      try await group.next()
      group.cancelAll()

      await XCTAssertThrowsRPCErrorAsync {
        try await client.connect(lazily: false)
      } errorHandler: { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
    }
  }

  func testCloseWhenUnconnected() {
    let client = makeClient()

    XCTAssertNoThrow(client.close())
  }

  func testCloseWhenClosed() {
    let client = makeClient()
    client.close()

    XCTAssertNoThrow(client.close())
  }

  func testConnectSuccessfullyAndThenClose() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }
      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
      }

      try await group.next()
      client.close()
    }
  }

  func testOpenStreamWhenUnconnected() async throws {
    let client = makeClient()

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.withStream(descriptor: .init(service: "test", method: "test")) { _ in
          // Once the pending stream is opened, close the client to new connections,
          // so that, once this closure is executed and this stream is closed,
          // the client will return from `connect(lazily:)`.
          client.close()
        }
      }

      group.addTask {
        // Add a sleep to make sure connection happens after `withStream` has been called,
        // to test pending streams are handled correctly.
        try await Task.sleep(for: .milliseconds(100))
        try await client.connect(lazily: false)
      }

      try await group.waitForAll()
    }
  }

  func testOpenStreamWhenClosed() async {
    let client = makeClient()

    client.close()

    await XCTAssertThrowsRPCErrorAsync {
      try await client.withStream(descriptor: .init(service: "test", method: "test")) { _ in }
    } errorHandler: { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testOpenStreamSuccessfullyAndThenClose() async throws {
    let server = InProcessServerTransport()
    let client = makeClient(server: server)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }

      group.addTask {
        try await client.withStream(descriptor: .init(service: "test", method: "test")) { stream in
          try await stream.outbound.write(.message([1]))
          stream.outbound.finish()
          let receivedMessages = try await stream.inbound.collect()

          XCTAssertEqual(receivedMessages, [.message([42])])
        }
      }

      group.addTask {
        for try await stream in server.listen() {
          let receivedMessages = try await stream.inbound.collect()
          try await stream.outbound.write(RPCResponsePart.message([42]))
          stream.outbound.finish()

          XCTAssertEqual(receivedMessages, [.message([1])])
        }
      }

      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
        client.close()
      }

      try await group.next()
      group.cancelAll()
    }
  }

  func testExecutionConfiguration() {
    let policy = HedgingPolicy(
      maximumAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )
    let defaultConfiguration = ClientRPCExecutionConfiguration(hedgingPolicy: policy)
    var configurations = ClientRPCExecutionConfigurationCollection(
      defaultConfiguration: defaultConfiguration
    )

    var client = InProcessClientTransport(server: .init(), executionConfigurations: configurations)

    let firstDescriptor = MethodDescriptor(service: "test", method: "first")
    XCTAssertEqual(client.executionConfiguration(forMethod: firstDescriptor), defaultConfiguration)

    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let overrideConfiguration = ClientRPCExecutionConfiguration(retryPolicy: retryPolicy)
    configurations[firstDescriptor] = overrideConfiguration
    client = InProcessClientTransport(server: .init(), executionConfigurations: configurations)
    let secondDescriptor = MethodDescriptor(service: "test", method: "second")
    XCTAssertEqual(client.executionConfiguration(forMethod: firstDescriptor), overrideConfiguration)
    XCTAssertEqual(client.executionConfiguration(forMethod: secondDescriptor), defaultConfiguration)
  }

  func testOpenMultipleStreamsThenClose() async throws {
    let server = InProcessServerTransport()
    let client = makeClient(server: server)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }

      group.addTask {
        try await client.withStream(descriptor: .init(service: "test", method: "test")) { stream in
          try await Task.sleep(for: .milliseconds(100))
        }
      }

      group.addTask {
        try await client.withStream(descriptor: .init(service: "test", method: "test")) { stream in
          try await Task.sleep(for: .milliseconds(100))
        }
      }

      group.addTask {
        try await Task.sleep(for: .milliseconds(50))
        client.close()
      }

      try await group.next()
    }
  }

  func makeClient(
    configuration: ClientRPCExecutionConfiguration? = nil,
    server: InProcessServerTransport = InProcessServerTransport()
  ) -> InProcessClientTransport {
    let defaultPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )

    return InProcessClientTransport(
      server: server,
      executionConfigurations: .init(
        defaultConfiguration: configuration ?? .init(retryPolicy: defaultPolicy)
      )
    )
  }
}
