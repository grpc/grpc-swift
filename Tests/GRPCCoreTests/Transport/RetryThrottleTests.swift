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

final class RetryThrottleTests: XCTestCase {
  func testThrottleOnInit() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
    // Start with max tokens, so permitted.
    XCTAssertTrue(throttle.isRetryPermitted)
    XCTAssertEqual(throttle.maximumTokens, 10)
    XCTAssertEqual(throttle.tokens, 10)
    XCTAssertEqual(throttle.tokenRatio, 0.1)
  }

  func testThrottleIgnoresMoreThanThreeDecimals() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1239)
    XCTAssertEqual(throttle.tokenRatio, 0.123)
  }

  func testFailureReducesTokens() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
    XCTAssertEqual(throttle.tokens, 10)
    XCTAssert(throttle.isRetryPermitted)

    throttle.recordFailure()
    XCTAssertEqual(throttle.tokens, 9)
    XCTAssert(throttle.isRetryPermitted)

    throttle.recordFailure()
    XCTAssertEqual(throttle.tokens, 8)
    XCTAssert(throttle.isRetryPermitted)

    throttle.recordFailure()
    XCTAssertEqual(throttle.tokens, 7)
    XCTAssert(throttle.isRetryPermitted)

    throttle.recordFailure()
    XCTAssertEqual(throttle.tokens, 6)
    XCTAssert(throttle.isRetryPermitted)

    // Drop to threshold, retries no longer allowed.
    throttle.recordFailure()
    XCTAssertEqual(throttle.tokens, 5)
    XCTAssertFalse(throttle.isRetryPermitted)
  }

  func testTokensCantDropBelowZero() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
    for _ in 0 ..< 1000 {
      throttle.recordFailure()
      XCTAssertGreaterThanOrEqual(throttle.tokens, 0)
    }
    XCTAssertEqual(throttle.tokens, 0)
  }

  func testSuccessIncreasesTokens() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)

    // Drop to zero.
    for _ in 0 ..< 10 {
      throttle.recordFailure()
    }
    XCTAssertEqual(throttle.tokens, 0)

    // Start recording successes.
    throttle.recordSuccess()
    XCTAssertEqual(throttle.tokens, 0.1)

    throttle.recordSuccess()
    XCTAssertEqual(throttle.tokens, 0.2)

    throttle.recordSuccess()
    XCTAssertEqual(throttle.tokens, 0.3)
  }

  func testTokensCantRiseAboveMax() {
    let throttle = RetryThrottle(maximumTokens: 10, tokenRatio: 0.1)
    XCTAssertEqual(throttle.tokens, 10)
    throttle.recordSuccess()
    XCTAssertEqual(throttle.tokens, 10)
  }
}
