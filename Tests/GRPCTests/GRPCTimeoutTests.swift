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

class GRPCTimeoutTests: GRPCTestCase {
  func testNegativeTimeoutThrows() throws {
    XCTAssertThrowsError(try GRPCTimeout.seconds(-10)) { error in
      XCTAssertEqual(error as? GRPCTimeoutError, GRPCTimeoutError.negative)
    }
  }

  func testTooLargeTimeout() throws {
    XCTAssertThrowsError(try GRPCTimeout.seconds(100_000_000)) { error in
      XCTAssertEqual(error as? GRPCTimeoutError, GRPCTimeoutError.tooManyDigits)
    }
  }

  func testRoundingNegativeTimeout() {
    let timeout: GRPCTimeout = .seconds(rounding: -10)
    XCTAssertEqual(String(describing: timeout), "0S")
    XCTAssertEqual(timeout.nanoseconds, 0)
  }

  func testRoundingNanosecondsTimeout() throws {
    let timeout: GRPCTimeout = .nanoseconds(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .microseconds(123457))

    // 123_456_789 (nanoseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (microseconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457u")

    // 123_457 (microseconds) * 1_000
    //   = 123_457_000 (nanoseconds)
    XCTAssertEqual(timeout.nanoseconds, 123_457_000)
  }

  func testRoundingMicrosecondsTimeout() throws {
    let timeout: GRPCTimeout = .microseconds(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .milliseconds(123457))

    // 123_456_789 (microseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (milliseconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457m")

    // 123_457 (milliseconds) * 1_000 * 1_000
    //   = 123_457_000_000 (nanoseconds)
    XCTAssertEqual(timeout.nanoseconds, 123_457_000_000)
  }

  func testRoundingMillisecondsTimeout() throws {
    let timeout: GRPCTimeout = .milliseconds(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .seconds(123457))

    // 123_456_789 (milliseconds) / 1_000
    //   = 123_456.789
    //   = 123_457 (seconds, rounded up)
    XCTAssertEqual(String(describing: timeout), "123457S")

    // 123_457 (milliseconds) * 1_000 * 1_000 * 1_000
    //   = 123_457_000_000_000 (nanoseconds)
    XCTAssertEqual(timeout.nanoseconds, 123_457_000_000_000)
  }

  func testRoundingSecondsTimeout() throws {
    let timeout: GRPCTimeout = .seconds(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .minutes(2057614))

    // 123_456_789 (seconds) / 60
    //   = 2_057_613.15
    //   = 2_057_614 (minutes, rounded up)
    XCTAssertEqual(String(describing: timeout), "2057614M")

    // 2_057_614 (minutes) * 60 * 1_000 * 1_000 * 1_000
    //   = 123_456_840_000_000_000 (nanoseconds)
    XCTAssertEqual(timeout.nanoseconds, 123_456_840_000_000_000)
  }

  func testRoundingMinutesTimeout() throws {
    let timeout: GRPCTimeout = .minutes(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .hours(2057614))

    // 123_456_789 (minutes) / 60
    //   = 2_057_613.15
    //   = 2_057_614 (hours, rounded up)
    XCTAssertEqual(String(describing: timeout), "2057614H")

    // 123_457 (minutes) * 60 * 60 * 1_000 * 1_000 * 1_000
    //   = 7_407_410_400_000_000_000 (nanoseconds)
    XCTAssertEqual(timeout.nanoseconds, 7_407_410_400_000_000_000)
  }

  func testRoundingHoursTimeout() throws {
    let timeout: GRPCTimeout = .hours(rounding: 123_456_789)
    XCTAssertEqual(timeout, try .hours(99_999_999))

    // Hours are the largest unit of time we have (as per the gRPC spec) so we can't round to a
    // different unit. In this case we clamp to the largest value.
    XCTAssertEqual(String(describing: timeout), "99999999H")
    // Unfortunately the largest value representable by the specification is too long to represent
    // in nanoseconds within 64 bits, again the value is clamped.
    XCTAssertEqual(timeout.nanoseconds, Int64.max)
  }
}
