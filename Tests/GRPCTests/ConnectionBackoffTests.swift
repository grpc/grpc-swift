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

class ConnectionBackoffTests: GRPCTestCase {
  var backoff = ConnectionBackoff()

  func testExpectedValuesWithNoJitter() {
    self.backoff.jitter = 0.0
    self.backoff.multiplier = 2.0
    self.backoff.initialBackoff = 1.0
    self.backoff.maximumBackoff = 16.0
    self.backoff.minimumConnectionTimeout = 4.2

    let timeoutAndBackoff = self.backoff.prefix(5)

    let expectedBackoff: [TimeInterval] = [1.0, 2.0, 4.0, 8.0, 16.0]
    XCTAssertEqual(expectedBackoff, timeoutAndBackoff.map { $0.backoff })

    let expectedTimeout: [TimeInterval] = [4.2, 4.2, 4.2, 8.0, 16.0]
    XCTAssertEqual(expectedTimeout, timeoutAndBackoff.map { $0.timeout })
  }

  func testBackoffWithNoJitter() {
    self.backoff.jitter = 0.0
    for (i, backoff) in self.backoff.prefix(100).map({ $0.backoff }).enumerated() {
      let expected = min(pow(self.backoff.initialBackoff * self.backoff.multiplier, Double(i)),
                         self.backoff.maximumBackoff)
      XCTAssertEqual(expected, backoff, accuracy: 1e-6)
    }
  }

  func testBackoffWithJitter() {
    for (i, timeoutAndBackoff) in self.backoff.prefix(100).enumerated() {
      let unjittered = min(pow(self.backoff.initialBackoff * self.backoff.multiplier, Double(i)),
                           self.backoff.maximumBackoff)
      let halfJitterRange = self.backoff.jitter * unjittered
      let jitteredRange = (unjittered-halfJitterRange)...(unjittered+halfJitterRange)
      XCTAssert(jitteredRange.contains(timeoutAndBackoff.backoff))
    }
  }

  func testBackoffDoesNotExceedMaximum() {
    // Since jitter is applied after checking against the maximum allowed backoff, the maximum
    // backoff can still be exceeded if jitter is non-zero.
    self.backoff.jitter = 0.0

    for backoff in self.backoff.prefix(100).map({ $0.backoff }) {
      XCTAssertLessThanOrEqual(backoff, self.backoff.maximumBackoff)
    }
  }

  func testConnectionTimeoutAlwaysGreatherThanOrEqualToMinimum() {
    for connectionTimeout in self.backoff.prefix(100).map({ $0.timeout }) {
      XCTAssertGreaterThanOrEqual(connectionTimeout, self.backoff.minimumConnectionTimeout)
    }
  }
}
