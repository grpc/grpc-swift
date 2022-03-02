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
@testable import GRPC
import XCTest

class GRPCStatusTests: GRPCTestCase {
  func testStatusDescriptionWithoutMessage() {
    XCTAssertEqual(
      "ok (0)",
      String(describing: GRPCStatus(code: .ok, message: nil))
    )

    XCTAssertEqual(
      "aborted (10)",
      String(describing: GRPCStatus(code: .aborted, message: nil))
    )

    XCTAssertEqual(
      "internal error (13)",
      String(describing: GRPCStatus(code: .internalError, message: nil))
    )
  }

  func testStatusDescriptionWithWithMessageWithoutCause() {
    XCTAssertEqual(
      "ok (0): OK",
      String(describing: GRPCStatus(code: .ok, message: "OK"))
    )

    XCTAssertEqual(
      "resource exhausted (8): a resource was exhausted",
      String(describing: GRPCStatus(code: .resourceExhausted, message: "a resource was exhausted"))
    )

    XCTAssertEqual(
      "failed precondition (9): invalid state",
      String(describing: GRPCStatus(code: .failedPrecondition, message: "invalid state"))
    )
  }

  func testStatusDescriptionWithMessageWithCause() {
    struct UnderlyingError: Error, CustomStringConvertible {
      var description: String { "underlying error description" }
    }
    let cause = UnderlyingError()
    XCTAssertEqual(
      "internal error (13): unknown error processing request, cause: \(cause.description)",
      String(describing: GRPCStatus(
        code: .internalError,
        message: "unknown error processing request",
        cause: cause
      ))
    )
  }

  func testStatusDescriptionWithoutMessageWithCause() {
    struct UnderlyingError: Error, CustomStringConvertible {
      var description: String { "underlying error description" }
    }
    let cause = UnderlyingError()
    XCTAssertEqual(
      "internal error (13), cause: \(cause.description)",
      String(describing: GRPCStatus(
        code: .internalError,
        message: nil,
        cause: cause
      ))
    )
  }

  func testCoWSemanticsModifyingMessage() {
    let nilStorageID = GRPCStatus.ok.testingOnly_storageObjectIdentifier
    var status = GRPCStatus(code: .resourceExhausted)

    // No message/cause, so uses the nil backing storage.
    XCTAssertEqual(status.testingOnly_storageObjectIdentifier, nilStorageID)

    status.message = "no longer using the nil backing storage"
    let storageID = status.testingOnly_storageObjectIdentifier
    XCTAssertNotEqual(storageID, nilStorageID)
    XCTAssertEqual(status.message, "no longer using the nil backing storage")

    // The storage of status should be uniquely ref'd, so setting message to nil should not change
    // the backing storage (even if the nil storage could now be used).
    status.message = nil
    XCTAssertEqual(status.testingOnly_storageObjectIdentifier, storageID)
    XCTAssertNil(status.message)
  }

  func testCoWSemanticsModifyingCause() {
    let nilStorageID = GRPCStatus.ok.testingOnly_storageObjectIdentifier
    var status = GRPCStatus(code: .cancelled)

    // No message/cause, so uses the nil backing storage.
    XCTAssertEqual(status.testingOnly_storageObjectIdentifier, nilStorageID)

    status.cause = ConnectionPoolError.tooManyWaiters(connectionError: nil)
    let storageID = status.testingOnly_storageObjectIdentifier
    XCTAssertNotEqual(storageID, nilStorageID)
    XCTAssert(status.cause is ConnectionPoolError)

    // The storage of status should be uniquely ref'd, so setting cause to nil should not change
    // the backing storage (even if the nil storage could now be used).
    status.cause = nil
    XCTAssertEqual(status.testingOnly_storageObjectIdentifier, storageID)
    XCTAssertNil(status.cause)
  }

  func testStatusesWithNoMessageOrCauseShareBackingStorage() {
    let validStatusCodes = (0 ... 16)
    let statuses: [GRPCStatus] = validStatusCodes.map { code in
      // 0...16 are all valid, '!' is fine.
      let code = GRPCStatus.Code(rawValue: code)!
      return GRPCStatus(code: code)
    }

    let storageIDs = Set(statuses.map { $0.testingOnly_storageObjectIdentifier })
    XCTAssertEqual(storageIDs.count, 1)
  }
}
