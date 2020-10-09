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
import XCTest

class ArrayBoundsCheckingTests: GRPCTestCase {
  func testBoundsCheckEmpty() {
    let array: [Int] = []

    XCTAssertNil(array[checked: array.startIndex])
    XCTAssertNil(array[checked: array.endIndex])
    XCTAssertNil(array[checked: -1])
  }

  func testBoundsCheckNonEmpty() {
    let array: [Int] = Array(0 ..< 10)

    var index = array.startIndex
    while index != array.endIndex {
      XCTAssertEqual(array[checked: index], array[index])
      array.formIndex(after: &index)
    }

    XCTAssertEqual(index, array.endIndex)
    XCTAssertNil(array[checked: index])
    XCTAssertNil(array[checked: -1])
  }
}
