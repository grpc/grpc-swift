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
import GRPCCore
import XCTest

final class StatusTests: XCTestCase {
  private static let statusCodeRawValue: [(Status.Code, Int)] = [
    (.ok, 0),
    (.cancelled, 1),
    (.unknown, 2),
    (.invalidArgument, 3),
    (.deadlineExceeded, 4),
    (.notFound, 5),
    (.alreadyExists, 6),
    (.permissionDenied, 7),
    (.resourceExhausted, 8),
    (.failedPrecondition, 9),
    (.aborted, 10),
    (.outOfRange, 11),
    (.unimplemented, 12),
    (.internalError, 13),
    (.unavailable, 14),
    (.dataLoss, 15),
    (.unauthenticated, 16),
  ]

  func testCustomStringConvertible() {
    XCTAssertDescription(Status(code: .ok, message: ""), #"ok: """#)
    XCTAssertDescription(Status(code: .dataLoss, message: "message"), #"dataLoss: "message""#)
    XCTAssertDescription(Status(code: .unknown, message: "message"), #"unknown: "message""#)
    XCTAssertDescription(Status(code: .aborted, message: "message"), #"aborted: "message""#)
  }

  func testStatusCodeRawValues() {
    for (code, expected) in Self.statusCodeRawValue {
      XCTAssertEqual(code.rawValue, expected, "\(code) had unexpected raw value")
    }
  }

  func testStatusCodeFromErrorCode() throws {
    XCTAssertEqual(Status.Code(RPCError.Code.cancelled), .cancelled)
    XCTAssertEqual(Status.Code(RPCError.Code.unknown), .unknown)
    XCTAssertEqual(Status.Code(RPCError.Code.invalidArgument), .invalidArgument)
    XCTAssertEqual(Status.Code(RPCError.Code.deadlineExceeded), .deadlineExceeded)
    XCTAssertEqual(Status.Code(RPCError.Code.notFound), .notFound)
    XCTAssertEqual(Status.Code(RPCError.Code.alreadyExists), .alreadyExists)
    XCTAssertEqual(Status.Code(RPCError.Code.permissionDenied), .permissionDenied)
    XCTAssertEqual(Status.Code(RPCError.Code.resourceExhausted), .resourceExhausted)
    XCTAssertEqual(Status.Code(RPCError.Code.failedPrecondition), .failedPrecondition)
    XCTAssertEqual(Status.Code(RPCError.Code.aborted), .aborted)
    XCTAssertEqual(Status.Code(RPCError.Code.outOfRange), .outOfRange)
    XCTAssertEqual(Status.Code(RPCError.Code.unimplemented), .unimplemented)
    XCTAssertEqual(Status.Code(RPCError.Code.internalError), .internalError)
    XCTAssertEqual(Status.Code(RPCError.Code.unavailable), .unavailable)
    XCTAssertEqual(Status.Code(RPCError.Code.dataLoss), .dataLoss)
    XCTAssertEqual(Status.Code(RPCError.Code.unauthenticated), .unauthenticated)
  }

  func testStatusCodeFromValidRawValue() {
    for (expected, rawValue) in Self.statusCodeRawValue {
      XCTAssertEqual(
        Status.Code(rawValue: rawValue),
        expected,
        "\(rawValue) didn't convert to expected code \(expected)"
      )
    }
  }

  func testStatusCodeFromInvalidRawValue() {
    // Internally represented as a `UInt8`; try all other values.
    for rawValue in UInt8(17) ... UInt8.max {
      XCTAssertNil(Status.Code(rawValue: Int(rawValue)))
    }

    // API accepts `Int` so try invalid `Int` values too.
    XCTAssertNil(Status.Code(rawValue: -1))
    XCTAssertNil(Status.Code(rawValue: 1000))
    XCTAssertNil(Status.Code(rawValue: .max))
  }

  func testEquatableConformance() {
    XCTAssertEqual(Status(code: .ok, message: ""), Status(code: .ok, message: ""))
    XCTAssertEqual(Status(code: .ok, message: "message"), Status(code: .ok, message: "message"))

    XCTAssertNotEqual(
      Status(code: .ok, message: ""),
      Status(code: .ok, message: "message")
    )

    XCTAssertNotEqual(
      Status(code: .ok, message: "message"),
      Status(code: .internalError, message: "message")
    )

    XCTAssertNotEqual(
      Status(code: .ok, message: "message"),
      Status(code: .ok, message: "different message")
    )
  }

  func testFitsInExistentialContainer() {
    XCTAssertLessThanOrEqual(MemoryLayout<Status>.size, 24)
  }
}
