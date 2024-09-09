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

import Testing

@testable import GRPCCore

struct TimeoutTests {
  @Test("Initialize from invalid String value", arguments: ["", "H", "123", "100000000S", "123j"])
  func initFromStringWithInvalidValue(_ value: String) throws {
    #expect(Timeout(decoding: value) == nil)
  }

  @Test(
    "Initialize from String",
    arguments: [
      ("123H", .hours(123)),
      ("123M", .minutes(123)),
      ("123S", .seconds(123)),
      ("123m", .milliseconds(123)),
      ("123u", .microseconds(123)),
      ("123n", .nanoseconds(123)),
    ] as [(String, Duration)]
  )
  func initFromString(_ value: String, expected: Duration) throws {
    let timeout = try #require(Timeout(decoding: value))
    #expect(timeout.duration == expected)
  }

  @Test(
    "Initialize from Duration",
    arguments: [
      .hours(123),
      .minutes(43),
      .seconds(12345),
      .milliseconds(100),
      .microseconds(100),
      .nanoseconds(100),
    ] as [Duration]
  )
  func initFromDuration(_ value: Duration) {
    let timeout = Timeout(duration: value)
    #expect(timeout.duration == value)
  }

  @Test(
    "Initialize from Duration with loss of precision",
    arguments: [
      // 111,111,111 seconds / 60 = 1,851,851.85 minutes -rounding up-> 1,851,852 minutes * 60 = 111,111,120 seconds
      (.seconds(111_111_111), .minutes(1_851_852)),

      // 9,999,999,999 seconds / 60 = 166,666,666.65 minutes -rounding up->
      // 166,666,667 minutes / 60 = 2,777,777.78 hours -rounding up->
      // 2,777,778 hours * 60 -> 166,666,680 minutes * 60 = 10,000,000,800 seconds
      (.seconds(9_999_999_999 as Int64), .hours(2_777_778)),

      // The conversion from seconds to hours results in a number that still has
      // more than the maximum allowed 8 digits, so we must clamp it.
      // Make sure that `Timeout.maxAmount` is the amount used for the resulting timeout.
      (.seconds(999_999_999_999 as Int64), .hours(Timeout.maxAmount)),

      // We can't convert seconds to nanoseconds because that would require at least
      // 9 digits, and the maximum allowed is 8: we expect to simply drop the nanoseconds.
      (Duration(secondsComponent: 1, attosecondsComponent: Int64(1e11)), .seconds(1)),
    ] as [(Duration, Duration)]
  )
  func initFromDurationWithLossOfPrecision(original: Duration, rounded: Duration) {
    let timeout = Timeout(duration: original)
    #expect(timeout.duration == rounded)
  }
}
