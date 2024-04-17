/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

@testable import GRPCHTTP2Core

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class ConnectionBackoffTests: XCTestCase {
  func testUnjitteredBackoff() {
    let backoff = ConnectionBackoff(
      initial: .seconds(10),
      max: .seconds(30),
      multiplier: 1.5,
      jitter: 0.0
    )

    var iterator = backoff.makeIterator()
    XCTAssertEqual(iterator.next(), .seconds(10))
    // 10 * 1.5 = 15 seconds
    XCTAssertEqual(iterator.next(), .seconds(15))
    // 15 * 1.5 = 22.5 seconds
    XCTAssertEqual(iterator.next(), .seconds(22.5))
    // 22.5 * 1.5 = 33.75 seconds, clamped to 30 seconds, all future values will be the same.
    XCTAssertEqual(iterator.next(), .seconds(30))
    XCTAssertEqual(iterator.next(), .seconds(30))
    XCTAssertEqual(iterator.next(), .seconds(30))
  }

  func testJitteredBackoff() {
    let backoff = ConnectionBackoff(
      initial: .seconds(10),
      max: .seconds(30),
      multiplier: 1.5,
      jitter: 0.1
    )

    var iterator = backoff.makeIterator()

    // Initial isn't jittered.
    XCTAssertEqual(iterator.next(), .seconds(10))

    // Next value should be 10 * 1.5 = 15 seconds ± 1.5 seconds
    var expected: ClosedRange<Duration> = .seconds(13.5) ... .seconds(16.5)
    XCTAssert(expected.contains(iterator.next()))

    // Next value should be 15 * 1.5 = 22.5 seconds ± 2.25 seconds
    expected = .seconds(20.25) ... .seconds(24.75)
    XCTAssert(expected.contains(iterator.next()))

    // Next value should be 22.5 * 1.5 = 33.75 seconds, clamped to 30 seconds ± 3 seconds.
    // All future values will be in the same range.
    expected = .seconds(27) ... .seconds(33)
    XCTAssert(expected.contains(iterator.next()))
    XCTAssert(expected.contains(iterator.next()))
    XCTAssert(expected.contains(iterator.next()))
  }
}
