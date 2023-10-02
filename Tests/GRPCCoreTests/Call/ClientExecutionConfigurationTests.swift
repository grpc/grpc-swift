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

final class ClientExecutionConfigurationTests: XCTestCase {
  func testRetryPolicyClampsMaxAttempts() {
    var policy = RetryPolicy(
      maxAttempts: 10,
      initialBackoff: .seconds(1),
      maxBackoff: .seconds(1),
      backoffMultiplier: 1.0,
      retryableStatusCodes: [.unavailable]
    )

    // Should be clamped on init
    XCTAssertEqual(policy.maxAttempts, 5)
    // and when modifying
    policy.maxAttempts = 10
    XCTAssertEqual(policy.maxAttempts, 5)
  }

  func testHedgingPolicyClampsMaxAttempts() {
    var policy = HedgingPolicy(
      maxAttempts: 10,
      hedgingDelay: .seconds(1),
      nonFatalStatusCodes: []
    )

    // Should be clamped on init
    XCTAssertEqual(policy.maxAttempts, 5)
    // and when modifying
    policy.maxAttempts = 10
    XCTAssertEqual(policy.maxAttempts, 5)
  }
}
