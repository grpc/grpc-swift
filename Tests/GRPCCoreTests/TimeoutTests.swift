import XCTest

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
@testable import GRPCCore

final class TimeoutTests: XCTestCase {
  func testDecodeInvalidTimeout_Empty() {
    let timeoutHeader = ""
    XCTAssertNil(Timeout(stringLiteral: timeoutHeader))
  }

  func testDecodeInvalidTimeout_NoAmount() {
    let timeoutHeader = "H"
    XCTAssertNil(Timeout(stringLiteral: timeoutHeader))
  }

  func testDecodeInvalidTimeout_NoUnit() {
    let timeoutHeader = "123"
    XCTAssertNil(Timeout(stringLiteral: timeoutHeader))
  }

  func testDecodeInvalidTimeout_TooLongAmount() {
    let timeoutHeader = "100000000S"
    XCTAssertNil(Timeout(stringLiteral: timeoutHeader))
  }

  func testDecodeInvalidTimeout_InvalidUnit() {
    let timeoutHeader = "123j"
    XCTAssertNil(Timeout(stringLiteral: timeoutHeader))
  }

  func testDecodeValidTimeout_Hours() {
    let timeoutHeader = "123H"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.hours(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Minutes() {
    let timeoutHeader = "123M"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.minutes(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Seconds() {
    let timeoutHeader = "123S"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.seconds(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Milliseconds() {
    let timeoutHeader = "123m"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.milliseconds(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Microseconds() {
    let timeoutHeader = "123u"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.microseconds(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testDecodeValidTimeout_Nanoseconds() {
    let timeoutHeader = "123n"
    let timeout = Timeout(stringLiteral: timeoutHeader)
    XCTAssertNotNil(timeout)
    XCTAssertEqual(timeout!.duration, Duration.nanoseconds(123))
    XCTAssertEqual(timeout!.wireEncoding, timeoutHeader)
  }

  func testRoundingNegativeTimeout() {
    let timeout = Timeout(rounding: -10, unit: .seconds)
    XCTAssertEqual(String(describing: timeout), "0S")
    XCTAssertEqual(timeout.duration, .seconds(0))
  }

  func testRoundingNanosecondsTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .nanoseconds)
    XCTAssertEqual(timeout, Timeout(amount: 123_457, unit: .microseconds))

    // 123_456_789 (nanoseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (microseconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457u")
    XCTAssertEqual(timeout.duration, .microseconds(123_457))
  }

  func testRoundingMicrosecondsTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .microseconds)
    XCTAssertEqual(timeout, Timeout(amount: 123_457, unit: .milliseconds))

    // 123_456_789 (microseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (milliseconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457m")
    XCTAssertEqual(timeout.duration, .milliseconds(123_457))
  }

  func testRoundingMillisecondsTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .milliseconds)
    XCTAssertEqual(timeout, Timeout(amount: 123_457, unit: .seconds))

    // 123_456_789 (milliseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (seconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457S")
    XCTAssertEqual(timeout.duration, .seconds(123_457))
  }

  func testRoundingSecondsTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .seconds)
    XCTAssertEqual(timeout, Timeout(amount: 2_057_614, unit: .minutes))

    // 123_456_789 (seconds) / 60
    //   = 2_057_613.15
    //   = 2_057_614 (minutes, rounded up)
    XCTAssertEqual(String(describing: timeout), "2057614M")
    XCTAssertEqual(timeout.duration, .minutes(2_057_614))
  }

  func testRoundingMinutesTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .minutes)
    XCTAssertEqual(timeout, Timeout(amount: 2_057_614, unit: .hours))

    // 123_456_789 (minutes) / 60
    //   = 2_057_613.15
    //   = 2_057_614 (hours, rounded up)
    XCTAssertEqual(String(describing: timeout), "2057614H")
    XCTAssertEqual(timeout.duration, .hours(2_057_614))
  }

  func testRoundingHoursTimeout() throws {
    let timeout = Timeout(rounding: 123_456_789, unit: .hours)
    XCTAssertEqual(timeout, Timeout(amount: 99_999_999, unit: .hours))

    // Hours are the largest unit of time we have (as per the gRPC spec) so we can't round to a
    // different unit. In this case we clamp to the largest value.
    XCTAssertEqual(String(describing: timeout), "99999999H")
    XCTAssertEqual(timeout.duration, .hours(Timeout.maxAmount))
  }
}
