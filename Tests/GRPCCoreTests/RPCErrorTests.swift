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

final class RPCErrorTests: XCTestCase {
  private static let statusCodeRawValue: [(RPCError.Code, Int)] = [
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
    XCTAssertDescription(RPCError(code: .dataLoss, message: ""), #"dataLoss: """#)
    XCTAssertDescription(RPCError(code: .unknown, message: "message"), #"unknown: "message""#)
    XCTAssertDescription(RPCError(code: .aborted, message: "message"), #"aborted: "message""#)
  }

  func testErrorFromStatus() throws {
    var status = Status(code: .ok, message: "")
    // ok isn't an error
    XCTAssertNil(RPCError(status: status))

    status.code = .invalidArgument
    var error = try XCTUnwrap(RPCError(status: status))
    XCTAssertEqual(error.code, .invalidArgument)
    XCTAssertEqual(error.message, "")
    XCTAssertEqual(error.metadata, [:])

    status.code = .cancelled
    status.message = "an error message"
    error = try XCTUnwrap(RPCError(status: status))
    XCTAssertEqual(error.code, .cancelled)
    XCTAssertEqual(error.message, "an error message")
    XCTAssertEqual(error.metadata, [:])
  }

  func testErrorCodeFromStatusCode() throws {
    XCTAssertNil(RPCError.Code(Status.Code.ok))
    XCTAssertEqual(RPCError.Code(Status.Code.cancelled), .cancelled)
    XCTAssertEqual(RPCError.Code(Status.Code.unknown), .unknown)
    XCTAssertEqual(RPCError.Code(Status.Code.invalidArgument), .invalidArgument)
    XCTAssertEqual(RPCError.Code(Status.Code.deadlineExceeded), .deadlineExceeded)
    XCTAssertEqual(RPCError.Code(Status.Code.notFound), .notFound)
    XCTAssertEqual(RPCError.Code(Status.Code.alreadyExists), .alreadyExists)
    XCTAssertEqual(RPCError.Code(Status.Code.permissionDenied), .permissionDenied)
    XCTAssertEqual(RPCError.Code(Status.Code.resourceExhausted), .resourceExhausted)
    XCTAssertEqual(RPCError.Code(Status.Code.failedPrecondition), .failedPrecondition)
    XCTAssertEqual(RPCError.Code(Status.Code.aborted), .aborted)
    XCTAssertEqual(RPCError.Code(Status.Code.outOfRange), .outOfRange)
    XCTAssertEqual(RPCError.Code(Status.Code.unimplemented), .unimplemented)
    XCTAssertEqual(RPCError.Code(Status.Code.internalError), .internalError)
    XCTAssertEqual(RPCError.Code(Status.Code.unavailable), .unavailable)
    XCTAssertEqual(RPCError.Code(Status.Code.dataLoss), .dataLoss)
    XCTAssertEqual(RPCError.Code(Status.Code.unauthenticated), .unauthenticated)
  }

  func testEquatableConformance() {
    XCTAssertEqual(
      RPCError(code: .cancelled, message: ""),
      RPCError(code: .cancelled, message: "")
    )

    XCTAssertEqual(
      RPCError(code: .cancelled, message: "message"),
      RPCError(code: .cancelled, message: "message")
    )

    XCTAssertEqual(
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"]),
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"])
    )

    XCTAssertNotEqual(
      RPCError(code: .cancelled, message: ""),
      RPCError(code: .cancelled, message: "message")
    )

    XCTAssertNotEqual(
      RPCError(code: .cancelled, message: "message"),
      RPCError(code: .unknown, message: "message")
    )

    XCTAssertNotEqual(
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"]),
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "baz"])
    )
  }

  func testStatusCodeRawValues() {
    for (code, expected) in Self.statusCodeRawValue {
      XCTAssertEqual(code.rawValue, expected, "\(code) had unexpected raw value")
    }
  }
}
