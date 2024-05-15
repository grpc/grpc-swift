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

import XCTest

@testable import GRPCHTTP2Core

final class ProcessUniqueIDTests: XCTestCase {
  func testProcessUniqueIDIsUnique() {
    var ids: Set<ProcessUniqueID> = []
    for _ in 1 ... 100 {
      let (inserted, _) = ids.insert(ProcessUniqueID())
      XCTAssertTrue(inserted)
    }

    XCTAssertEqual(ids.count, 100)
  }

  func testProcessUniqueIDDescription() {
    let id = ProcessUniqueID()
    let description = String(describing: id)
    // We can't verify the exact description as we don't know what value to expect, we only
    // know that it'll be an integer.
    XCTAssertNotNil(UInt64(description))
  }

  func testSubchannelIDDescription() {
    let id = SubchannelID()
    let description = String(describing: id)
    XCTAssert(description.hasPrefix("subchan_"))
  }

  func testLoadBalancerIDDescription() {
    let id = LoadBalancerID()
    let description = String(describing: id)
    XCTAssert(description.hasPrefix("lb_"))
  }
}
