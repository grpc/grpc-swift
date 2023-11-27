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

final class TimeoutTests: XCTestCase {
  func testDecodeInvalidTimeout_Empty() {
    let timeoutHeader = ""
    XCTAssertNil(Timeout(decoding: timeoutHeader))
  }

  func testDecodeInvalidTimeout_NoAmount() {
    let timeoutHeader = "H"
    XCTAssertNil(Timeout(decoding: timeoutHeader))
  }

  func testDecodeInvalidTimeout_NoUnit() {
    let timeoutHeader = "123"
    XCTAssertNil(Timeout(decoding: timeoutHeader))
  }

  func testDecodeInvalidTimeout_TooLongAmount() {
    let timeoutHeader = "100000000S"
    XCTAssertNil(Timeout(decoding: timeoutHeader))
  }

  func testDecodeInvalidTimeout_InvalidUnit() {
    let timeoutHeader = "123j"
    XCTAssertNil(Timeout(decoding: timeoutHeader))
  }

  func testDecodeValidTimeout_Hours() throws {
    let timeoutHeader = "123H"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.hours(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Minutes() throws {
    let timeoutHeader = "123M"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.minutes(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Seconds() throws {
    let timeoutHeader = "123S"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.seconds(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Milliseconds() throws {
    let timeoutHeader = "123m"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.milliseconds(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Microseconds() throws {
    let timeoutHeader = "123u"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.microseconds(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Nanoseconds() throws {
    let timeoutHeader = "123n"
    let timeout = Timeout(decoding: timeoutHeader)
    let unwrappedTimeout = try XCTUnwrap(timeout)
    XCTAssertEqual(unwrappedTimeout.duration, Duration.nanoseconds(123))
    XCTAssertEqual(unwrappedTimeout.wireEncoding, timeoutHeader)
  }

  func testEncodeValidTimeout_Hours() {
    let duration = Duration.hours(123)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_Minutes() {
    let duration = Duration.minutes(43)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_Seconds() {
    let duration = Duration.seconds(12345)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_Seconds_TooLong_Minutes() {
    let duration = Duration.seconds(111_111_111)
    let timeout = Timeout(duration: duration)
    // The conversion from seconds to minutes results in a loss of precision.
    // 111,111,111 seconds / 60 = 1,851,851.85 minutes -rounding up-> 1,851,852 minutes * 60 = 111,111,120 seconds
    let expectedRoundedDuration = Duration.minutes(1_851_852)
    XCTAssertEqual(timeout.duration.components.seconds, expectedRoundedDuration.components.seconds)
    XCTAssertEqual(
      timeout.duration.components.attoseconds,
      expectedRoundedDuration.components.attoseconds
    )
  }

  func testEncodeValidTimeout_Seconds_TooLong_Hours() {
    let duration = Duration.seconds(9_999_999_999)
    let timeout = Timeout(duration: duration)
    // The conversion from seconds to hours results in a loss of precision.
    // 9,999,999,999 seconds / 60 = 166,666,666.65 minutes -rounding up->
    // 166,666,667 minutes / 60 = 2,777,777.78 hours -rounding up->
    // 2,777,778 hours * 60 -> 166,666,680 minutes * 60 = 10,000,000,800 seconds
    let expectedRoundedDuration = Duration.hours(2_777_778)
    XCTAssertEqual(timeout.duration.components.seconds, expectedRoundedDuration.components.seconds)
    XCTAssertEqual(
      timeout.duration.components.attoseconds,
      expectedRoundedDuration.components.attoseconds
    )
  }

  func testEncodeValidTimeout_Seconds_TooLong_MaxAmount() {
    let duration = Duration.seconds(999_999_999_999)
    let timeout = Timeout(duration: duration)
    // The conversion from seconds to hours results in a number that still has
    // more than the maximum allowed 8 digits, so we must clamp it.
    // Make sure that `Timeout.maxAmount` is the amount used for the resulting timeout.
    let expectedRoundedDuration = Duration.hours(Timeout.maxAmount)
    XCTAssertEqual(timeout.duration.components.seconds, expectedRoundedDuration.components.seconds)
    XCTAssertEqual(
      timeout.duration.components.attoseconds,
      expectedRoundedDuration.components.attoseconds
    )
  }

  func testEncodeValidTimeout_SecondsAndMilliseconds() {
    let duration = Duration(secondsComponent: 100, attosecondsComponent: Int64(1e+17))
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_SecondsAndMicroseconds() {
    let duration = Duration(secondsComponent: 1, attosecondsComponent: Int64(1e+14))
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_SecondsAndNanoseconds() {
    let duration = Duration(secondsComponent: 1, attosecondsComponent: Int64(1e+11))
    let timeout = Timeout(duration: duration)
    // We can't convert seconds to nanoseconds because that would require at least
    // 9 digits, and the maximum allowed is 8: we expect to simply drop the nanoseconds.
    let expectedRoundedDuration = Duration.seconds(1)
    XCTAssertEqual(timeout.duration.components.seconds, expectedRoundedDuration.components.seconds)
    XCTAssertEqual(
      timeout.duration.components.attoseconds,
      expectedRoundedDuration.components.attoseconds
    )
  }

  func testEncodeValidTimeout_Milliseconds() {
    let duration = Duration.milliseconds(100)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_Microseconds() {
    let duration = Duration.microseconds(100)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }

  func testEncodeValidTimeout_Nanoseconds() {
    let duration = Duration.nanoseconds(100)
    let timeout = Timeout(duration: duration)
    XCTAssertEqual(timeout.duration.components.seconds, duration.components.seconds)
    XCTAssertEqual(timeout.duration.components.attoseconds, duration.components.attoseconds)
  }
}
