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

@testable import BenchmarkUtils
import XCTest

class HistogramTests: XCTestCase {
  func testStats() {
    var histogram = Histogram()
    histogram.add(value: 1)
    histogram.add(value: 2)
    histogram.add(value: 3)

    XCTAssertEqual(histogram.countOfValuesSeen, 3)
    XCTAssertEqual(histogram.maxSeen, 3)
    XCTAssertEqual(histogram.minSeen, 1)
    XCTAssertEqual(histogram.sum, 6)
    XCTAssertEqual(histogram.sumOfSquares, 14)
  }

  func testBuckets() {
    var histogram = Histogram()
    histogram.add(value: 1)
    histogram.add(value: 1)
    histogram.add(value: 3)

    var twoSeen = false
    var oneSeen = false
    for bucket in histogram.buckets {
      switch bucket {
      case 0:
        break
      case 1:
        XCTAssertFalse(oneSeen)
        oneSeen = true
      case 2:
        XCTAssertFalse(twoSeen)
        twoSeen = true
      default:
        XCTFail()
      }
    }
    XCTAssertTrue(oneSeen)
    XCTAssertTrue(twoSeen)
  }

  func testMerge() {
    var histogram = Histogram()
    histogram.add(value: 1)
    histogram.add(value: 2)
    histogram.add(value: 3)

    let histogram2 = Histogram()
    histogram.add(value: 1)
    histogram.add(value: 1)
    histogram.add(value: 3)

    XCTAssertNoThrow(try histogram.merge(source: histogram2))

    XCTAssertEqual(histogram.countOfValuesSeen, 6)
    XCTAssertEqual(histogram.maxSeen, 3)
    XCTAssertEqual(histogram.minSeen, 1)
    XCTAssertEqual(histogram.sum, 11)
    XCTAssertEqual(histogram.sumOfSquares, 25)

    var threeSeen = false
    var twoSeen = false
    var oneSeen = false
    for bucket in histogram.buckets {
      switch bucket {
      case 0:
        break
      case 1:
        XCTAssertFalse(oneSeen)
        oneSeen = true
      case 2:
        XCTAssertFalse(twoSeen)
        twoSeen = true
      case 3:
        XCTAssertFalse(threeSeen)
        threeSeen = true
      default:
        XCTFail()
      }
    }
    XCTAssertTrue(oneSeen)
    XCTAssertTrue(twoSeen)
    XCTAssertTrue(threeSeen)
  }
}
