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
  fileprivate func makeHarnessForRetries(
    rejectUntilAttempt firstSuccessfulAttempt: Int,
    withCode code: RPCError.Code,
    consumeInboundStream: Bool = false
  ) -> ClientRPCExecutorTestHarness {
    return ClientRPCExecutorTestHarness(
      server: .attemptBased { attempt in
        guard attempt < firstSuccessfulAttempt else {
          return .echo
        }

        return .reject(
          withError: RPCError(code: code, message: ""),
          consumeInbound: consumeInboundStream
        )
      }
    )
  }

  func testRetriesEventuallySucceed() async throws {
    let harness = self.makeHarnessForRetries(
      rejectUntilAttempt: 3,
      withCode: .unavailable,
      consumeInboundStream: true
    )
    try await harness.bidirectional(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([0])
        try await $0.write([1])
        try await $0.write([2])
      },
      configuration: .retry(codes: [.unavailable])
    ) { response in
      XCTAssertEqual(
        response.metadata,
        [
          "foo": "bar",
          "grpc-previous-rpc-attempts": "2",
        ]
      )
      let messages = try await response.messages.collect()
      XCTAssertEqual(messages, [[0], [1], [2]])
    }

    // Success on the third attempt.
    XCTAssertEqual(harness.clientStreamsOpened, 3)
    XCTAssertEqual(harness.serverStreamsAccepted, 3)
  }

  func testRetriesRespectRetryableCodes() async throws {
    let harness = self.makeHarnessForRetries(rejectUntilAttempt: 3, withCode: .unavailable)
    try await harness.bidirectional(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([0, 1, 2])
      },
      configuration: .retry(codes: [.aborted])
    ) { response in
      switch response.accepted {
      case .success:
        XCTFail("Expected response to be rejected")
      case .failure(let error):
        XCTAssertEqual(error.code, .unavailable)
      }
    }

    // Error code wasn't retryable, only one stream.
    XCTAssertEqual(harness.clientStreamsOpened, 1)
    XCTAssertEqual(harness.serverStreamsAccepted, 1)
  }

  func testRetriesRespectRetryLimit() async throws {
    let harness = self.makeHarnessForRetries(rejectUntilAttempt: 5, withCode: .unavailable)
    try await harness.bidirectional(
      request: ClientRequest.Stream(metadata: ["foo": "bar"]) {
        try await $0.write([0, 1, 2])
      },
      configuration: .retry(maximumAttempts: 2, codes: [.unavailable])
    ) { response in
      switch response.accepted {
      case .success:
        XCTFail("Expected response to be rejected")
      case .failure(let error):
        XCTAssertEqual(error.code, .unavailable)
        XCTAssertEqual(Array(error.metadata[stringValues: "grpc-previous-rpc-attempts"]), ["1"])
      }
    }

    // Only two attempts permitted.
    XCTAssertEqual(harness.clientStreamsOpened, 2)
    XCTAssertEqual(harness.serverStreamsAccepted, 2)
  }

  func testRetriesCantBeExecutedForTooManyRequestMessages() async throws {
    let harness = self.makeHarnessForRetries(
      rejectUntilAttempt: 3,
      withCode: .unavailable,
      consumeInboundStream: true
    )

    try await harness.bidirectional(
      request: ClientRequest.Stream {
        for _ in 0 ..< 1000 {
          try await $0.write([])
        }
      },
      configuration: .retry(codes: [.unavailable])
    ) { response in
      switch response.accepted {
      case .success:
        XCTFail("Expected response to be rejected")
      case .failure(let error):
        XCTAssertEqual(error.code, .unavailable)
        XCTAssertFalse(error.metadata.contains { $0.key == "grpc-previous-rpc-attempts" })
      }
    }

    // The request stream can't be buffered as it's a) large, and b) the server consumes it before
    // responding. Even though the server responded with a retryable status code, the request buffer
    // was dropped so only one attempt was made.
    XCTAssertEqual(harness.clientStreamsOpened, 1)
    XCTAssertEqual(harness.serverStreamsAccepted, 1)
  }

  func testRetriesWithImmediateTimeout() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .sleepFor(duration: .milliseconds(250), then: .echo)
    )

    await XCTAssertThrowsErrorAsync {
      try await harness.bidirectional(
        request: ClientRequest.Stream {
          try await $0.write([0])
          try await $0.write([1])
          try await $0.write([2])
        },
        configuration: .retry(codes: [.unavailable], timeout: .zero)
      ) { response in
        XCTFail("Response not expected to be handled")
      }
    } errorHandler: { error in
      XCTAssert(error is CancellationError)
    }
  }

  func testRetriesWithTimeoutDuringFirstAttempt() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .sleepFor(duration: .milliseconds(250), then: .echo)
    )

    await XCTAssertThrowsErrorAsync {
      try await harness.bidirectional(
        request: ClientRequest.Stream {
          try await $0.write([0])
          try await $0.write([1])
          try await $0.write([2])
        },
        configuration: .retry(codes: [.unavailable], timeout: .milliseconds(50))
      ) { response in
        XCTFail("Response not expected to be handled")
      }
    } errorHandler: { error in
      XCTAssert(error is CancellationError)
    }
  }

  func testRetriesWithTimeoutDuringSecondAttempt() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .sleepFor(
        duration: .milliseconds(100),
        then: .reject(withError: RPCError(code: .unavailable, message: ""))
      )
    )

    await XCTAssertThrowsErrorAsync {
      try await harness.bidirectional(
        request: ClientRequest.Stream {
          try await $0.write([0])
          try await $0.write([1])
          try await $0.write([2])
        },
        configuration: .retry(codes: [.unavailable], timeout: .milliseconds(150))
      ) { response in
        XCTFail("Response not expected to be handled")
      }
    } errorHandler: { error in
      XCTAssert(error is CancellationError)
    }
  }

  func testRetriesWithServerPushback() async throws {
    let harness = ClientRPCExecutorTestHarness(
      server: .attemptBased { attempt in
        if attempt == 2 {
          return .echo
        } else {
          return .init { stream in
            // Use a short pushback to override the long configured retry delay.
            let status = Status(code: .unavailable, message: "")
            let metadata: Metadata = ["grpc-retry-pushback-ms": "10"]
            try await stream.outbound.write(.status(status, metadata))
          }
        }
      }
    )

    let retryPolicy = RetryPolicy(
      maximumAttempts: 5,
      initialBackoff: .seconds(60),
      maximumBackoff: .seconds(50),
      backoffMultiplier: 1,
      retryableStatusCodes: [.unavailable]
    )

    let start = ContinuousClock.now
    try await harness.bidirectional(
      request: ClientRequest.Stream {
        try await $0.write([0])
      },
      configuration: .init(names: [], executionPolicy: .retry(retryPolicy))
    ) { response in
      let end = ContinuousClock.now
      let duration = end - start
      // Loosely check whether the RPC completed in less than 60 seconds (i.e. the configured retry
      // delay). Allow lots of headroom to avoid false negatives; CI systems can be slow.
      XCTAssertLessThanOrEqual(duration, .seconds(5))
      XCTAssertEqual(Array(response.metadata[stringValues: "grpc-previous-rpc-attempts"]), ["1"])
    }
  }

  func testRetriesWithNegativeServerPushback() async throws {
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

      let retryPolicy = RetryPolicy(
        maximumAttempts: 5,
        initialBackoff: .seconds(60),
        maximumBackoff: .seconds(50),
        backoffMultiplier: 1,
        retryableStatusCodes: [.unavailable]
      )

      try await harness.bidirectional(
        request: ClientRequest.Stream {
          try await $0.write([0])
        },
        configuration: .init(names: [], executionPolicy: .retry(retryPolicy))
      ) { response in
        switch response.accepted {
        case .success:
          XCTFail("Expected RPC to fail")
        case .failure(let error):
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
extension MethodConfiguration {
  fileprivate static func retry(
    maximumAttempts: Int = 5,
    codes: Set<Status.Code>,
    timeout: Duration? = nil
  ) -> Self {
    let policy = RetryPolicy(
      maximumAttempts: maximumAttempts,
      initialBackoff: .milliseconds(10),
      maximumBackoff: .milliseconds(100),
      backoffMultiplier: 1.6,
      retryableStatusCodes: codes
    )

    return Self(names: [], timeout: timeout, executionPolicy: .retry(policy))
  }
}
