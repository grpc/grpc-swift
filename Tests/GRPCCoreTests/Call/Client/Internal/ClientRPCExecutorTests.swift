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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class ClientRPCExecutorTests: XCTestCase {
  func testUnaryEcho() async throws {
    let tester = ClientRPCExecutorTestHarness(server: .echo)
    try await tester.unary(
      request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
    ) { response in
      XCTAssertEqual(response.metadata, ["foo": "bar"])
      XCTAssertEqual(try response.message, [1, 2, 3])
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testClientStreamingEcho() async throws {
    let tester = ClientRPCExecutorTestHarness(server: .echo)
    try await tester.clientStreaming(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([1, 2, 3])
      }
    ) { response in
      XCTAssertEqual(response.metadata, ["foo": "bar"])
      XCTAssertEqual(try response.message, [1, 2, 3])
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testServerStreamingEcho() async throws {
    let tester = ClientRPCExecutorTestHarness(server: .echo)
    try await tester.serverStreaming(
      request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
    ) { response in
      XCTAssertEqual(response.metadata, ["foo": "bar"])
      let messages = try await response.messages.collect()
      XCTAssertEqual(messages, [[1, 2, 3]])
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testBidirectionalStreamingEcho() async throws {
    let tester = ClientRPCExecutorTestHarness(server: .echo)
    try await tester.bidirectional(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([1, 2, 3])
      }
    ) { response in
      XCTAssertEqual(response.metadata, ["foo": "bar"])
      let messages = try await response.messages.collect()
      XCTAssertEqual(messages, [[1, 2, 3]])
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testUnaryRejectedByServer() async throws {
    let error = RPCError(code: .unauthenticated, message: "", metadata: ["metadata": "error"])
    let tester = ClientRPCExecutorTestHarness(server: .reject(withError: error))
    try await tester.unary(
      request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
    ) { response in
      XCTAssertThrowsRPCError(try response.message) {
        XCTAssertEqual($0, error)
      }
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testClientStreamingRejectedByServer() async throws {
    let error = RPCError(code: .unauthenticated, message: "", metadata: ["metadata": "error"])
    let tester = ClientRPCExecutorTestHarness(server: .reject(withError: error))
    try await tester.clientStreaming(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([1, 2, 3])
      }
    ) { response in
      XCTAssertThrowsRPCError(try response.message) {
        XCTAssertEqual($0, error)
      }
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testServerStreamingRejectedByServer() async throws {
    let error = RPCError(code: .unauthenticated, message: "", metadata: ["metadata": "error"])
    let tester = ClientRPCExecutorTestHarness(server: .reject(withError: error))
    try await tester.serverStreaming(
      request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
    ) { response in
      await XCTAssertThrowsRPCErrorAsync {
        try await response.messages.collect()
      } errorHandler: {
        XCTAssertEqual($0, error)
      }
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testBidirectionalRejectedByServer() async throws {
    let error = RPCError(code: .unauthenticated, message: "", metadata: ["metadata": "error"])
    let tester = ClientRPCExecutorTestHarness(server: .reject(withError: error))
    try await tester.bidirectional(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([1, 2, 3])
      }
    ) { response in
      await XCTAssertThrowsRPCErrorAsync {
        try await response.messages.collect()
      } errorHandler: {
        XCTAssertEqual($0, error)
      }
    }

    XCTAssertEqual(tester.clientStreamsOpened, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 1)
  }

  func testUnaryUnableToOpenStream() async throws {
    let tester = ClientRPCExecutorTestHarness(
      transport: .throwsOnStreamCreation(code: .aborted),
      server: .failTest
    )

    await XCTAssertThrowsRPCErrorAsync {
      try await tester.unary(
        request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
      ) { _ in }
    } errorHandler: { error in
      XCTAssertEqual(error.code, .aborted)
    }

    XCTAssertEqual(tester.clientStreamsOpened, 0)
    XCTAssertEqual(tester.clientStreamOpenFailures, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 0)
  }

  func testClientStreamingUnableToOpenStream() async throws {
    let tester = ClientRPCExecutorTestHarness(
      transport: .throwsOnStreamCreation(code: .aborted),
      server: .failTest
    )

    await XCTAssertThrowsRPCErrorAsync {
      try await tester.clientStreaming(
        request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
          try await $0.write([1, 2, 3])
        }
      ) { _ in }
    } errorHandler: { error in
      XCTAssertEqual(error.code, .aborted)
    }

    XCTAssertEqual(tester.clientStreamsOpened, 0)
    XCTAssertEqual(tester.clientStreamOpenFailures, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 0)
  }

  func testServerStreamingUnableToOpenStream() async throws {
    let tester = ClientRPCExecutorTestHarness(
      transport: .throwsOnStreamCreation(code: .aborted),
      server: .failTest
    )

    await XCTAssertThrowsRPCErrorAsync {
      try await tester.serverStreaming(
        request: ClientRequest.Single(message: [1, 2, 3], metadata: ["foo": "bar"])
      ) { _ in }
    } errorHandler: {
      XCTAssertEqual($0.code, .aborted)
    }

    XCTAssertEqual(tester.clientStreamsOpened, 0)
    XCTAssertEqual(tester.clientStreamOpenFailures, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 0)
  }

  func testBidirectionalUnableToOpenStream() async throws {
    let tester = ClientRPCExecutorTestHarness(
      transport: .throwsOnStreamCreation(code: .aborted),
      server: .failTest
    )

    await XCTAssertThrowsRPCErrorAsync {
      try await tester.bidirectional(
        request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
          try await $0.write([1, 2, 3])
        }
      ) { _ in }
    } errorHandler: {
      XCTAssertEqual($0.code, .aborted)
    }

    XCTAssertEqual(tester.clientStreamsOpened, 0)
    XCTAssertEqual(tester.clientStreamOpenFailures, 1)
    XCTAssertEqual(tester.serverStreamsAccepted, 0)
  }

  func testTimeoutIsPropagated() async throws {
    // 'nil' means no retires or hedging, just try to execute the RPC once.
    var policies: [RPCExecutionPolicy?] = [nil]

    let retryPolicy = RetryPolicy(
      maximumAttempts: 5,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.6,
      retryableStatusCodes: [.unavailable]
    )
    policies.append(.retry(retryPolicy))

    let hedgingPolicy = HedgingPolicy(
      maximumAttempts: 5,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: [.unavailable]
    )
    policies.append(.hedge(hedgingPolicy))

    for policy in policies {
      let timeout = Duration.seconds(120)
      var options = CallOptions.defaults
      options.timeout = timeout
      options.executionPolicy = policy

      let tester = ClientRPCExecutorTestHarness(transport: .inProcess, server: .echo)
      try await tester.unary(
        request: ClientRequest.Single(message: []),
        options: options
      ) { response in
        let timeoutMetadata = Array(response.metadata[stringValues: "grpc-timeout"])
        let parsed = try XCTUnwrap(timeoutMetadata.first.flatMap { Timeout(decoding: $0) })

        // The timeout is handled as a deadline internally and gets converted back to a timeout
        // when transmitted as metadata, so allow some leeway when checking the value.
        let leeway = Duration.seconds(1)
        let acceptable: ClosedRange<Duration> = timeout - leeway ... timeout + leeway

        XCTAssert(acceptable.contains(parsed.duration))
      }
    }
  }
}
