/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import GRPC
import XCTest

class ConnectionBackoffTests: XCTestCase {
  var backoff: ConnectionBackoff!

  override func setUp() {
    self.backoff = ConnectionBackoff()
  }

  func testExpectedValuesWithNoJitter() {
    self.backoff.jitter = 0.0
    self.backoff.multiplier = 2.0
    self.backoff.initialBackoff = 1.0
    self.backoff.maximumBackoff = 16.0

    let expected: [TimeInterval] = [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]
    let backoffs = Array(self.backoff).map { $0.backoff }

    XCTAssertEqual(expected, backoffs)
  }

  func testBackoffWithNoJitter() {
    self.backoff.jitter = 0.0

    for (i, timeoutAndBackoff) in self.backoff.enumerated() {
      if i == 0 {
        // Initial backoff should always be zero.
        XCTAssertEqual(0.0, timeoutAndBackoff.backoff)
        XCTAssertEqual(self.backoff.minimumConnectionTimeout, timeoutAndBackoff.timeout)
      } else {
        let expected = min(pow(self.backoff.initialBackoff * self.backoff.multiplier, Double(i-1)),
                           self.backoff.maximumBackoff)
        XCTAssertEqual(expected, timeoutAndBackoff.backoff, accuracy: 1e-6)
      }
    }
  }

  func testBackoffWithJitter() {
    for (i, timeoutAndBackoff) in self.backoff.enumerated() {
      if i == 0 {
        // Initial backoff should always be zero.
        XCTAssertEqual(0.0, timeoutAndBackoff.backoff)
        XCTAssertEqual(self.backoff.minimumConnectionTimeout, timeoutAndBackoff.timeout)
      } else {
        let unjittered = min(pow(self.backoff.initialBackoff * self.backoff.multiplier, Double(i-1)),
                             self.backoff.maximumBackoff)
        let halfJitterRange = self.backoff.jitter * unjittered
        let jitteredRange = (unjittered-halfJitterRange)...(unjittered+halfJitterRange)
        XCTAssert(jitteredRange.contains(timeoutAndBackoff.backoff))
      }
    }
  }

  func testBackoffDoesNotExceedMaximum() {
    self.backoff.maximumBackoff = self.backoff.initialBackoff
    // Since jitter is applied after checking against the maximum allowed backoff, the maximum
    // backoff can still be exceeded if jitter is non-zero.
    self.backoff.jitter = 0.0

    for (i, timeoutAndBackoff) in self.backoff.enumerated() {
      if i == 0 {
        // Initial backoff should always be zero.
        XCTAssertEqual(0.0, timeoutAndBackoff.backoff)
        XCTAssertEqual(self.backoff.minimumConnectionTimeout, timeoutAndBackoff.timeout)
      } else {
        XCTAssertEqual(timeoutAndBackoff.backoff, self.backoff.maximumBackoff)
      }
    }
  }

  func testConnectionTimeoutAlwaysGreatherThanOrEqualToMinimum() {
    for (connectionTimeout, _) in self.backoff {
      XCTAssertGreaterThanOrEqual(connectionTimeout, self.backoff.minimumConnectionTimeout)
    }
  }
}
