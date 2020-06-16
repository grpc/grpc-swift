/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
@testable import GRPC
import NIO
import XCTest

class TimeLimitTests: GRPCTestCase {
  func testTimeout() {
    XCTAssertEqual(TimeLimit.timeout(.seconds(42)).timeout, .seconds(42))
    XCTAssertNil(TimeLimit.none.timeout)
    XCTAssertNil(TimeLimit.deadline(.now()).timeout)
  }

  func testDeadline() {
    XCTAssertEqual(TimeLimit.deadline(.uptimeNanoseconds(42)).deadline, .uptimeNanoseconds(42))
    XCTAssertNil(TimeLimit.none.deadline)
    XCTAssertNil(TimeLimit.timeout(.milliseconds(31415)).deadline)
  }

  func testMakeDeadline() {
    XCTAssertEqual(TimeLimit.none.makeDeadline(), .distantFuture)
    XCTAssertEqual(TimeLimit.timeout(.nanoseconds(.max)).makeDeadline(), .distantFuture)

    let now = NIODeadline.now()
    XCTAssertEqual(TimeLimit.deadline(now).makeDeadline(), now)
    XCTAssertEqual(TimeLimit.deadline(.distantFuture).makeDeadline(), .distantFuture)
  }
}
