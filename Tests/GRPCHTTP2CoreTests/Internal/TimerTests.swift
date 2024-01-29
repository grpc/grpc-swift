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

import Atomics
import NIOEmbedded
import XCTest

@testable import GRPCHTTP2Core

internal final class TimerTests: XCTestCase {
  func testScheduleOneOffTimer() {
    let loop = EmbeddedEventLoop()
    defer { try! loop.close() }

    var value = 0

    var timer = Timer(delay: .seconds(1), repeat: false)
    timer.schedule(on: loop) {
      XCTAssertEqual(value, 0)
      value += 1
    }

    loop.advanceTime(by: .milliseconds(999))
    XCTAssertEqual(value, 0)
    loop.advanceTime(by: .milliseconds(1))
    XCTAssertEqual(value, 1)

    // Run again to make sure the task wasn't repeated.
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(value, 1)
  }

  func testCancelOneOffTimer() {
    let loop = EmbeddedEventLoop()
    defer { try! loop.close() }

    var timer = Timer(delay: .seconds(1), repeat: false)
    timer.schedule(on: loop) {
      XCTFail("Timer wasn't cancelled")
    }

    loop.advanceTime(by: .milliseconds(999))
    timer.cancel()
    loop.advanceTime(by: .milliseconds(1))
  }

  func testScheduleRepeatedTimer() throws {
    let loop = EmbeddedEventLoop()
    defer { try! loop.close() }

    var values = [Int]()

    var timer = Timer(delay: .seconds(1), repeat: true)
    timer.schedule(on: loop) {
      values.append(values.count)
    }

    loop.advanceTime(by: .milliseconds(999))
    XCTAssertEqual(values, [])
    loop.advanceTime(by: .milliseconds(1))
    XCTAssertEqual(values, [0])

    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values, [0, 1])
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values, [0, 1, 2])

    timer.cancel()
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values, [0, 1, 2])
  }

  func testCancelRepeatedTimer() {
    let loop = EmbeddedEventLoop()
    defer { try! loop.close() }

    var timer = Timer(delay: .seconds(1), repeat: true)
    timer.schedule(on: loop) {
      XCTFail("Timer wasn't cancelled")
    }

    loop.advanceTime(by: .milliseconds(999))
    timer.cancel()
    loop.advanceTime(by: .milliseconds(1))
  }
}
