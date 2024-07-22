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
import GRPCCore
import GRPCHTTP2Core
import NIOEmbedded
import XCTest

internal final class TimerTests: XCTestCase {
  func testScheduleOneOffTimer() {
    let loop = EmbeddedEventLoop()
    defer { try! loop.close() }

    let value = LockedValueBox(0)
    var timer = Timer(delay: .seconds(1), repeat: false)
    timer.schedule(on: loop) {
      value.withLockedValue {
        XCTAssertEqual($0, 0)
        $0 += 1
      }
    }

    loop.advanceTime(by: .milliseconds(999))
    XCTAssertEqual(value.withLockedValue { $0 }, 0)
    loop.advanceTime(by: .milliseconds(1))
    XCTAssertEqual(value.withLockedValue { $0 }, 1)

    // Run again to make sure the task wasn't repeated.
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(value.withLockedValue { $0 }, 1)
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

    let values = LockedValueBox([Int]())
    var timer = Timer(delay: .seconds(1), repeat: true)
    timer.schedule(on: loop) {
      values.withLockedValue { $0.append($0.count) }
    }

    loop.advanceTime(by: .milliseconds(999))
    XCTAssertEqual(values.withLockedValue { $0 }, [])
    loop.advanceTime(by: .milliseconds(1))
    XCTAssertEqual(values.withLockedValue { $0 }, [0])

    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values.withLockedValue { $0 }, [0, 1])
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values.withLockedValue { $0 }, [0, 1, 2])

    timer.cancel()
    loop.advanceTime(by: .seconds(1))
    XCTAssertEqual(values.withLockedValue { $0 }, [0, 1, 2])
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
