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
import XCTest
@testable import GRPC

class StopwatchTests: GRPCTestCase {
  func testElapsed() {
    var time: TimeInterval = 0.0

    let stopwatch = Stopwatch {
      return Date(timeIntervalSinceNow: time)
    }

    time = 1.0
    XCTAssertEqual(1.0, stopwatch.elapsed(), accuracy: 0.001)

    time = 42.0
    XCTAssertEqual(42.0, stopwatch.elapsed(), accuracy: 0.001)

    time = 3650.123
    XCTAssertEqual(3650.123, stopwatch.elapsed(), accuracy: 0.001)
  }
}
