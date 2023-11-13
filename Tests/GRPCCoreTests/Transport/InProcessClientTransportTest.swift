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

final class InProcessClientTransportTest: XCTestCase {
  func testConnectWhenConnected() async throws {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }
      group.addTask {
        try await client.connect(lazily: false)
      }

      try await group.next()
      await XCTAssertThrowsRPCErrorAsync({ try await group.next() }) { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
      group.cancelAll()
    }
  }

  func testConnectWhenClosed() async {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    client.close()

    await XCTAssertThrowsRPCErrorAsync({ try await client.connect(lazily: false) }) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testConnectWhenClosedAfterCancellation() async throws {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.connect(lazily: false)
      }
      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
      }

      try await group.next()
      group.cancelAll()

      await XCTAssertThrowsRPCErrorAsync({ try await client.connect(lazily: false) }) { error in
        XCTAssertEqual(error.code, .failedPrecondition)
      }
    }
  }

  func testCloseWhenUnconnected() {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    XCTAssertNoThrow(client.close())
  }

  func testCloseWhenClosed() {
    func testCloseWhenUnconnected() {
      let retryPolicy = RetryPolicy(
        maximumAttempts: 10,
        initialBackoff: .seconds(1),
        maximumBackoff: .seconds(1),
        backoffMultiplier: 1.0,
        retryableStatusCodes: [.unavailable]
      )
      let client = InProcessClientTransport(
        server: .init(),
        executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
      )

      client.close()
      XCTAssertNoThrow(client.close())
    }
  }

  func testConnectSuccessfullyAndThenClose() async throws {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

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

  func testOpenStreamWhenUnconnected() async {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    await XCTAssertThrowsRPCErrorAsync({
      try await client.withStream(descriptor: .init(service: "test", method: "test")) { _ in }
    }) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testOpenStreamWhenClosed() async {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let client = InProcessClientTransport(
      server: .init(),
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    client.close()

    await XCTAssertThrowsRPCErrorAsync({
      try await client.withStream(descriptor: .init(service: "test", method: "test")) { _ in }
    }) { error in
      XCTAssertEqual(error.code, .failedPrecondition)
    }
  }

  func testOpenStreamSuccessfullyAndThenClose() async throws {
    let retryPolicy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )
    let server = InProcessServerTransport()
    let client = InProcessClientTransport(
      server: server,
      executionConfigurations: .init(defaultConfiguration: .init(retryPolicy: retryPolicy))
    )

    let receivedMessages = LockedValueBox([[UInt8]]())

    try await client.connect(lazily: false)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await client.withStream(descriptor: .init(service: "test", method: "test")) { stream in
          try await stream.outbound.write(.message([1]))
          for try await response in stream.inbound {
            guard case .message(let message) = response else {
              XCTFail()
              fatalError()
            }
            receivedMessages.withLockedValue({ $0.append(message) })
          }
        }
      }

      group.addTask {
        for try await stream in server.listen() {
          try await stream.outbound.write(
            contentsOf: stream.inbound.map({ requestPart in
              guard case .message(let message) = requestPart else {
                XCTFail()
                fatalError()
              }
              receivedMessages.withLockedValue({ $0.append(message) })
              return RPCResponsePart.message([42])
            })
          )
        }
      }

      group.addTask {
        try await Task.sleep(for: .milliseconds(100))
        client.close()
        await XCTAssertThrowsRPCErrorAsync {
          try await client.withStream(descriptor: .init(service: "test", method: "test")) { _ in }
        } errorHandler: { error in
          XCTAssertEqual(error.code, .failedPrecondition)
          XCTAssertEqual(error.message, "The client transport is closed.")
        }

      }

      try await group.next()
      let finalReceivedMessages = receivedMessages.withLockedValue { $0 }
      XCTAssertEqual(finalReceivedMessages, [[1], [42]])
      group.cancelAll()
    }

    await XCTAssertThrowsRPCErrorAsync {
      try await client.connect(lazily: false)
    } errorHandler: { error in
      XCTAssertEqual(error.code, .failedPrecondition)
      XCTAssertEqual(error.message, "Can't connect to server, transport is closed.")
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
    configurations.addConfiguration(
      overrideConfiguration,
      forMethod: firstDescriptor
    )
    client = InProcessClientTransport(server: .init(), executionConfigurations: configurations)
    let secondDescriptor = MethodDescriptor(service: "test", method: "second")
    XCTAssertEqual(client.executionConfiguration(forMethod: firstDescriptor), overrideConfiguration)
    XCTAssertEqual(client.executionConfiguration(forMethod: secondDescriptor), defaultConfiguration)
  }
}
