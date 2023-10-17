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
final class ClientRPCExecutionConfigurationTests: XCTestCase {
  func testRetryPolicyClampsMaxAttempts() {
    var policy = RetryPolicy(
      maximumAttempts: 10,
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )

    // Should be clamped on init
    XCTAssertEqual(policy.maximumAttempts, 5)
    // and when modifying
    policy.maximumAttempts = 10
    XCTAssertEqual(policy.maximumAttempts, 5)
  }

  func testHedgingPolicyClampsMaxAttempts() {
    var policy = HedgingPolicy(
      maximumAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )

    // Should be clamped on init
    XCTAssertEqual(policy.maximumAttempts, 5)
    // and when modifying
    policy.maximumAttempts = 10
    XCTAssertEqual(policy.maximumAttempts, 5)
  }
}
