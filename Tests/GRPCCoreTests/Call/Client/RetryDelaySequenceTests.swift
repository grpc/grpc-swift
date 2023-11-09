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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class RetryDelaySequenceTests: XCTestCase {
  func testSequence() {
    let policy = RetryPolicy(
      maximumAttempts: 1,  // ignored here
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(8),
      backoffMultiplier: 2.0,
      retryableStatusCodes: [.aborted]  // ignored here
    )

    let sequence = RetryDelaySequence(policy: policy)
    var iterator = sequence.makeIterator()

    // The iterator will never return 'nil', '!' is safe.
    XCTAssertLessThanOrEqual(iterator.next()!, .seconds(1))
    XCTAssertLessThanOrEqual(iterator.next()!, .seconds(2))
    XCTAssertLessThanOrEqual(iterator.next()!, .seconds(4))
    XCTAssertLessThanOrEqual(iterator.next()!, .seconds(8))
    XCTAssertLessThanOrEqual(iterator.next()!, .seconds(8))  // Clamped
  }

  func testSequenceSupportsMultipleIteration() {
    let policy = RetryPolicy(
      maximumAttempts: 1,  // ignored here
      initialBackoff: .seconds(1),
      maximumBackoff: .seconds(8),
      backoffMultiplier: 2.0,
      retryableStatusCodes: [.aborted]  // ignored here
    )

    let sequence = RetryDelaySequence(policy: policy)
    for _ in 0 ..< 10 {
      var iterator = sequence.makeIterator()
      // The iterator will never return 'nil', '!' is safe.
      XCTAssertLessThanOrEqual(iterator.next()!, .seconds(1))
      XCTAssertLessThanOrEqual(iterator.next()!, .seconds(2))
      XCTAssertLessThanOrEqual(iterator.next()!, .seconds(4))
      XCTAssertLessThanOrEqual(iterator.next()!, .seconds(8))
      XCTAssertLessThanOrEqual(iterator.next()!, .seconds(8))  // Clamped
    }
  }

  func testDurationToDouble() {
    let testData: [(Duration, Double)] = [
      (.zero, 0.0),
      (.seconds(1), 1.0),
      (.milliseconds(1500), 1.5),
      (.nanoseconds(1_000_000_000), 1.0),
      (.nanoseconds(3_141_592_653), 3.141592653),
    ]

    for (duration, expected) in testData {
      XCTAssertEqual(RetryDelaySequence.Iterator._durationToTimeInterval(duration), expected)
    }
  }

  func testDoubleToDuration() {
    let testData: [(Double, Duration)] = [
      (0.0, .zero),
      (1.0, .seconds(1)),
      (1.5, .milliseconds(1500)),
      (1.0, .nanoseconds(1_000_000_000)),
      (3.141592653, .nanoseconds(3_141_592_653)),
    ]

    for (seconds, expected) in testData {
      let actual = RetryDelaySequence.Iterator._timeIntervalToDuration(seconds)
      XCTAssertEqual(actual.components.seconds, expected.components.seconds)
      // We lose some precision in the conversion, that's fine.
      XCTAssertEqual(actual.components.attoseconds / 1_000, expected.components.attoseconds / 1_000)
    }
  }
}
