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
import GRPC
import XCTest

class StatusCountsTests: XCTestCase {
  func testIgnoreOK() {
    var statusCounts = StatusCounts()
    statusCounts.add(status: .ok)
    XCTAssertEqual(statusCounts.counts.count, 0)
  }

  func testMessageBuilding() {
    var statusCounts = StatusCounts()
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .alreadyExists)

    let counts = statusCounts.counts
    XCTAssertEqual(counts.count, 2)
    for stat in counts {
      switch stat.key {
      case GRPCStatus.Code.aborted.rawValue:
        XCTAssertEqual(stat.value, 2)
      case GRPCStatus.Code.alreadyExists.rawValue:
        XCTAssertEqual(stat.value, 1)
      default:
        XCTFail()
      }
    }
  }

  func testMergeEmpty() {
    var statusCounts = StatusCounts()
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .alreadyExists)

    let otherCounts = StatusCounts()

    statusCounts.merge(source: otherCounts)

    let counts = statusCounts.counts
    XCTAssertEqual(counts.count, 2)
    for stat in counts {
      switch stat.key {
      case GRPCStatus.Code.aborted.rawValue:
        XCTAssertEqual(stat.value, 2)
      case GRPCStatus.Code.alreadyExists.rawValue:
        XCTAssertEqual(stat.value, 1)
      default:
        XCTFail()
      }
    }
  }

  func testMergeToEmpty() {
    var statusCounts = StatusCounts()

    var otherCounts = StatusCounts()
    otherCounts.add(status: .aborted)
    otherCounts.add(status: .aborted)
    otherCounts.add(status: .alreadyExists)

    statusCounts.merge(source: otherCounts)

    let counts = statusCounts.counts
    XCTAssertEqual(counts.count, 2)
    for stat in counts {
      switch stat.key {
      case GRPCStatus.Code.aborted.rawValue:
        XCTAssertEqual(stat.value, 2)
      case GRPCStatus.Code.alreadyExists.rawValue:
        XCTAssertEqual(stat.value, 1)
      default:
        XCTFail()
      }
    }
  }

  func testMerge() {
    var statusCounts = StatusCounts()
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .aborted)
    statusCounts.add(status: .alreadyExists)

    var otherCounts = StatusCounts()
    otherCounts.add(status: .alreadyExists)
    otherCounts.add(status: .dataLoss)

    statusCounts.merge(source: otherCounts)

    let counts = statusCounts.counts
    XCTAssertEqual(counts.count, 3)
    for stat in counts {
      switch stat.key {
      case GRPCStatus.Code.aborted.rawValue:
        XCTAssertEqual(stat.value, 2)
      case GRPCStatus.Code.alreadyExists.rawValue:
        XCTAssertEqual(stat.value, 2)
      case GRPCStatus.Code.dataLoss.rawValue:
        XCTAssertEqual(stat.value, 1)
      default:
        XCTFail()
      }
    }
  }
}
