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

import GRPCCore
import XCTest

final class CompressionAlgorithmTests: XCTestCase {
  func testCompressionAlgorithmSetContains() {
    var algorithms = CompressionAlgorithmSet()
    XCTAssertFalse(algorithms.contains(.gzip))
    XCTAssertFalse(algorithms.contains(.deflate))
    XCTAssertFalse(algorithms.contains(.none))

    algorithms.formUnion(.gzip)
    XCTAssertTrue(algorithms.contains(.gzip))
    XCTAssertFalse(algorithms.contains(.deflate))
    XCTAssertFalse(algorithms.contains(.none))

    algorithms.formUnion(.deflate)
    XCTAssertTrue(algorithms.contains(.gzip))
    XCTAssertTrue(algorithms.contains(.deflate))
    XCTAssertFalse(algorithms.contains(.none))

    algorithms.formUnion(.none)
    XCTAssertTrue(algorithms.contains(.gzip))
    XCTAssertTrue(algorithms.contains(.deflate))
    XCTAssertTrue(algorithms.contains(.none))
  }

  func testCompressionAlgorithmSetElements() {
    var algorithms = CompressionAlgorithmSet.all
    XCTAssertEqual(Array(algorithms.elements), [.none, .deflate, .gzip])

    algorithms.subtract(.deflate)
    XCTAssertEqual(Array(algorithms.elements), [.none, .gzip])

    algorithms.subtract(.none)
    XCTAssertEqual(Array(algorithms.elements), [.gzip])

    algorithms.subtract(.gzip)
    XCTAssertEqual(Array(algorithms.elements), [])
  }

  func testCompressionAlgorithmSetElementsIgnoresUnknownBits() {
    let algorithms = CompressionAlgorithmSet(rawValue: .max)
    XCTAssertEqual(Array(algorithms.elements), [.none, .deflate, .gzip])
  }
}
