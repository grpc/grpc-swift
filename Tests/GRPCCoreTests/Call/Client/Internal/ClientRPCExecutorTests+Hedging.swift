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
import XCTest

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ClientRPCExecutorTests {
  func testHedgingWhenAllAttemptsResultInNonFatalCodes() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .reject(withError: RPCError(code: .unavailable, message: ""))
    )

    try await harness.bidirectional(
      request: ClientRequest.Stream {
        try await $0.write([0])
        try await $0.write([1])
        try await $0.write([2])
      },
      options: .hedge(nonFatalCodes: [.unavailable])
    ) { response in
      XCTAssertRejected(response) { error in
        XCTAssertEqual(error.code, .unavailable)
        XCTAssertEqual(Array(error.metadata[stringValues: "grpc-previous-rpc-attempts"]), ["4"])
      }
    }

    // All five attempts fail.
    XCTAssertEqual(harness.clientStreamsOpened, 5)
    XCTAssertEqual(harness.serverStreamsAccepted, 5)
  }

  func testHedgingRespectsFatalStatusCodes() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .reject(withError: RPCError(code: .aborted, message: ""))
    )

    try await harness.bidirectional(
      request: ClientRequest.Stream {
        try await $0.write([0])
        try await $0.write([1])
        try await $0.write([2])
      },
      // Set a long delay to reduce the risk of racing the second attempt and checking the number
      // of streams being opened.
      options: .hedge(delay: .seconds(5), nonFatalCodes: [])
    ) { response in
      XCTAssertRejected(response) { error in
        XCTAssertEqual(error.code, .aborted)
      }
    }

    // The first response is fatal.
    XCTAssertEqual(harness.clientStreamsOpened, 1)
    XCTAssertEqual(harness.serverStreamsAccepted, 1)

  }

  func testHedgingWhenServerIsSlowToRespond() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .attemptBased { attempt in
        if attempt == 5 {
          return .echo
        } else {
          return .sleepFor(
            duration: .seconds(60),
            then: .reject(withError: RPCError(code: .unavailable, message: ""))
          )
        }
      }
    )

    let start = ContinuousClock.now
    try await harness.bidirectional(
      request: ClientRequest.Stream {
        try await $0.write([0])
        try await $0.write([1])
        try await $0.write([2])
      },
      options: .hedge(
        maximumAttempts: 5,
        delay: .milliseconds(10),
        nonFatalCodes: [.unavailable]
      )
    ) { response in
      let duration = ContinuousClock.now - start
      // Should take significantly less than the 60 seconds of the slow responders to get a
      // response from the fast responder. Use a large amount of leeway to avoid false positives
      // in slow CI systems.
      XCTAssertLessThanOrEqual(duration, .milliseconds(500))

      let messages = try await response.messages.collect()
      XCTAssertEqual(messages, [[0], [1], [2]])
      XCTAssertEqual(Array(response.metadata[stringValues: "grpc-previous-rpc-attempts"]), ["4"])
    }

    // Only the 5th attempt succeeds.
    XCTAssertEqual(harness.clientStreamsOpened, 5)
    XCTAssertEqual(harness.serverStreamsAccepted, 5)
  }

  func testHedgingWithServerPushback() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .attemptBased { attempt in
        if attempt == 2 {
          return .echo
        } else {
          return .init { stream in
            let status = Status(code: .unavailable, message: "")
            let metadata: Metadata = ["grpc-retry-delay-ms": "10"]
            try await stream.outbound.write(.status(status, metadata))
          }
        }
      }
    )

    let start = ContinuousClock.now
    try await harness.bidirectional(
      request: ClientRequest.Stream {
        try await $0.write([0])
        try await $0.write([1])
        try await $0.write([2])
      },
      options: .hedge(
        maximumAttempts: 5,
        delay: .seconds(60),  // High delay, server pushback will override this.
        nonFatalCodes: [.unavailable]
      )
    ) { response in
      let duration = ContinuousClock.now - start
      // Should take significantly less than the 60 seconds. The server pushback is only 10 ms which
      // should override the configured delay. Use a large amount of leeway to avoid false positives
      // in slow CI systems.
      XCTAssertLessThanOrEqual(duration, .milliseconds(500))

      let messages = try await response.messages.collect()
      XCTAssertEqual(messages, [[0], [1], [2]])
      XCTAssertEqual(Array(response.metadata[stringValues: "grpc-previous-rpc-attempts"]), ["1"])
    }

    // Only the 2nd attempt succeeds.
    XCTAssertEqual(harness.clientStreamsOpened, 2)
    XCTAssertEqual(harness.serverStreamsAccepted, 2)
  }

  func testHedgingWithNegativeServerPushback() async throws {
    // Negative and values which can't be parsed should halt retries.
    for pushback in ["-1", "not-an-int"] {
      let harness = ClientRPCExecutorTestHarness(
        server: .reject(
          withError: RPCError(
            code: .unavailable,
            message: "",
            metadata: ["grpc-retry-pushback-ms": "\(pushback)"]
          )
        )
      )

      try await harness.bidirectional(
        request: ClientRequest.Stream {
          try await $0.write([0])
        },
        options: .hedge(delay: .seconds(60), nonFatalCodes: [.unavailable])
      ) { response in
        XCTAssertRejected(response) { error in
          XCTAssertEqual(error.code, .unavailable)
        }
      }

      // Only one attempt should be made.
      XCTAssertEqual(harness.clientStreamsOpened, 1)
      XCTAssertEqual(harness.serverStreamsAccepted, 1)
    }
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension CallOptions {
  fileprivate static func hedge(
    maximumAttempts: Int = 5,
    delay: Duration = .milliseconds(25),
    nonFatalCodes: Set<Status.Code>,
    timeout: Duration? = nil
  ) -> Self {
    let policy = HedgingPolicy(
      maximumAttempts: maximumAttempts,
      hedgingDelay: delay,
      nonFatalStatusCodes: nonFatalCodes
    )

    var options = CallOptions.defaults
    options.executionPolicy = .hedge(policy)
    return options
  }
}
