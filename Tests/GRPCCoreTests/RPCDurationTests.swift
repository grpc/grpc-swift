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

final class RPCDurationTests: XCTestCase {
  func testExcessivePositiveValuesAreClamped() {
    let value = UInt64.max
    let expected = RPCDuration.nanoseconds(Int64.max)
    XCTAssertEqual(expected.nanoseconds, Int64.max)

    XCTAssertEqual(RPCDuration.nanoseconds(value), expected)
    XCTAssertEqual(RPCDuration.microseconds(value), expected)
    XCTAssertEqual(RPCDuration.milliseconds(value), expected)
    XCTAssertEqual(RPCDuration.seconds(value), expected)
    XCTAssertEqual(RPCDuration.minutes(value), expected)
    XCTAssertEqual(RPCDuration.hours(value), expected)
  }

  func testExcessiveNegativeValuesAreClamped() {
    let value = Int64.min
    let expected = RPCDuration.nanoseconds(Int64.min)
    XCTAssertEqual(expected.nanoseconds, Int64.min)

    XCTAssertEqual(RPCDuration.nanoseconds(value), expected)
    XCTAssertEqual(RPCDuration.microseconds(value), expected)
    XCTAssertEqual(RPCDuration.milliseconds(value), expected)
    XCTAssertEqual(RPCDuration.seconds(value), expected)
    XCTAssertEqual(RPCDuration.minutes(value), expected)
    XCTAssertEqual(RPCDuration.hours(value), expected)
  }

  func testConversion() throws {
    XCTAssertEqual(RPCDuration.nanoseconds(1), .nanoseconds(1))
    XCTAssertEqual(RPCDuration.microseconds(1), .nanoseconds(1000))
    XCTAssertEqual(RPCDuration.milliseconds(1), .nanoseconds(1_000_000))
    XCTAssertEqual(RPCDuration.seconds(1), .nanoseconds(1_000_000_000))
    XCTAssertEqual(RPCDuration.minutes(1), .nanoseconds(60_000_000_000))
    XCTAssertEqual(RPCDuration.hours(1), .nanoseconds(3_600_000_000_000))
  }

  func testConversionToDuration() {
    let rpcDuration = RPCDuration.hours(1)
    let duration = Duration(rpcDuration)
    XCTAssertEqual(duration.components.seconds, 3600)
    XCTAssertEqual(duration.components.attoseconds, 0)
  }

  func testConversionFromDuration() {
    let duration = Duration(secondsComponent: 3600, attosecondsComponent: 1_000_000_000)
    let rpcDuration = RPCDuration(duration)
    XCTAssertEqual(rpcDuration.nanoseconds, 3_600_000_000_001)
  }
}
