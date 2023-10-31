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

import XCTest

@testable import GRPCCore

final class MetadataGRPCTests: XCTestCase {
  func testPreviousRPCAttemptsValidValues() {
    let testData = [("0", 0), ("1", 1), ("-1", -1)]
    for (value, expected) in testData {
      let metadata: Metadata = ["grpc-previous-rpc-attempts": "\(value)"]
      XCTAssertEqual(metadata.previousRPCAttempts, expected)
    }
  }

  func testPreviousRPCAttemptsInvalidValues() {
    let values = ["foo", "42.0"]
    for value in values {
      let metadata: Metadata = ["grpc-previous-rpc-attempts": "\(value)"]
      XCTAssertNil(metadata.previousRPCAttempts)
    }
  }

  func testSetPreviousRPCAttemptsToValue() {
    var metadata: Metadata = [:]

    metadata.previousRPCAttempts = 42
    XCTAssertEqual(metadata, ["grpc-previous-rpc-attempts": "42"])

    metadata.previousRPCAttempts = nil
    XCTAssertEqual(metadata, [:])

    for i in 0 ..< 5 {
      metadata.addString("\(i)", forKey: "grpc-previous-rpc-attempts")
    }
    XCTAssertEqual(metadata.count, 5)

    // Should remove old values.
    metadata.previousRPCAttempts = 42
    XCTAssertEqual(metadata, ["grpc-previous-rpc-attempts": "42"])
  }

  func testRetryPushbackValidDelay() {
    let testData: [(String, Duration)] = [
      ("0", .zero),
      ("1", Duration(secondsComponent: 0, attosecondsComponent: 1_000_000_000_000_000)),
      ("999", Duration(secondsComponent: 0, attosecondsComponent: 999_000_000_000_000_000)),
      ("1000", Duration(secondsComponent: 1, attosecondsComponent: 0)),
      ("1001", Duration(secondsComponent: 1, attosecondsComponent: 1_000_000_000_000_000)),
      ("1999", Duration(secondsComponent: 1, attosecondsComponent: 999_000_000_000_000_000)),
    ]

    for (value, expectedDuration) in testData {
      let metadata: Metadata = ["grpc-retry-pushback-ms": "\(value)"]
      XCTAssertEqual(metadata.retryPushback, .retryAfter(expectedDuration))
    }
  }

  func testRetryPushbackInvalidDelay() {
    let testData: [String] = ["-1", "-inf", "not-a-number", "42.0"]

    for value in testData {
      let metadata: Metadata = ["grpc-retry-pushback-ms": "\(value)"]
      XCTAssertEqual(metadata.retryPushback, .stopRetrying)
    }
  }

  func testRetryPushbackNoValuePresent() {
    let metadata: Metadata = [:]
    XCTAssertNil(metadata.retryPushback)
  }
}
