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
import Testing

@Suite("RPCError Tests")
struct RPCErrorTests {
  @Test("Custom String Convertible")
  func testCustomStringConvertible() {
    #expect(String(describing: RPCError(code: .dataLoss, message: "")) == #"dataLoss: """#)
    #expect(
      String(describing: RPCError(code: .unknown, message: "message")) == #"unknown: "message""#
    )
    #expect(
      String(describing: RPCError(code: .aborted, message: "message")) == #"aborted: "message""#
    )

    struct TestError: Error {}
    #expect(
      String(describing: RPCError(code: .aborted, message: "message", cause: TestError()))
        == #"aborted: "message" (cause: "TestError()")"#
    )
  }

  @Test("Error from Status")
  func testErrorFromStatus() throws {
    var status = Status(code: .ok, message: "")
    // ok isn't an error
    #expect(RPCError(status: status) == nil)

    status.code = .invalidArgument
    var error = try #require(RPCError(status: status))
    #expect(error.code == .invalidArgument)
    #expect(error.message == "")
    #expect(error.metadata == [:])

    status.code = .cancelled
    status.message = "an error message"
    error = try #require(RPCError(status: status))
    #expect(error.code == .cancelled)
    #expect(error.message == "an error message")
    #expect(error.metadata == [:])
  }

  @Test(
    "Error Code from Status Code",
    arguments: [
      (Status.Code.ok, nil),
      (Status.Code.cancelled, RPCError.Code.cancelled),
      (Status.Code.unknown, RPCError.Code.unknown),
      (Status.Code.invalidArgument, RPCError.Code.invalidArgument),
      (Status.Code.deadlineExceeded, RPCError.Code.deadlineExceeded),
      (Status.Code.notFound, RPCError.Code.notFound),
      (Status.Code.alreadyExists, RPCError.Code.alreadyExists),
      (Status.Code.permissionDenied, RPCError.Code.permissionDenied),
      (Status.Code.resourceExhausted, RPCError.Code.resourceExhausted),
      (Status.Code.failedPrecondition, RPCError.Code.failedPrecondition),
      (Status.Code.aborted, RPCError.Code.aborted),
      (Status.Code.outOfRange, RPCError.Code.outOfRange),
      (Status.Code.unimplemented, RPCError.Code.unimplemented),
      (Status.Code.internalError, RPCError.Code.internalError),
      (Status.Code.unavailable, RPCError.Code.unavailable),
      (Status.Code.dataLoss, RPCError.Code.dataLoss),
      (Status.Code.unauthenticated, RPCError.Code.unauthenticated),
    ]
  )
  func testErrorCodeFromStatusCode(statusCode: Status.Code, rpcErrorCode: RPCError.Code?) throws {
    #expect(RPCError.Code(statusCode) == rpcErrorCode)
  }

  @Test("Equatable Conformance")
  func testEquatableConformance() {
    #expect(
      RPCError(code: .cancelled, message: "")
        == RPCError(code: .cancelled, message: "")
    )

    #expect(
      RPCError(code: .cancelled, message: "message")
        == RPCError(code: .cancelled, message: "message")
    )

    #expect(
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"])
        == RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"])
    )

    #expect(
      RPCError(code: .cancelled, message: "")
        != RPCError(code: .cancelled, message: "message")
    )

    #expect(
      RPCError(code: .cancelled, message: "message")
        != RPCError(code: .unknown, message: "message")
    )

    #expect(
      RPCError(code: .cancelled, message: "message", metadata: ["foo": "bar"])
        != RPCError(code: .cancelled, message: "message", metadata: ["foo": "baz"])
    )
  }

  @Test(
    "Status Code Raw Values",
    arguments: [
      (RPCError.Code.cancelled, 1),
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
  )
  func testStatusCodeRawValues(statusCode: RPCError.Code, rawValue: Int) {
    #expect(statusCode.rawValue == rawValue, "\(statusCode) had unexpected raw value")
  }

  @Test("Flatten causes with same status code")
  func testFlattenCausesWithSameStatusCode() {
    let error1 = RPCError(code: .unknown, message: "Error 1.")
    let error2 = RPCError(code: .unknown, message: "Error 2.", cause: error1)
    let error3 = RPCError(code: .dataLoss, message: "Error 3.", cause: error2)
    let error4 = RPCError(code: .aborted, message: "Error 4.", cause: error3)
    let error5 = RPCError(
      code: .aborted,
      message: "Error 5.",
      cause: error4
    )

    let unknownMerged = RPCError(code: .unknown, message: "Error 2. Error 1.")
    let dataLossMerged = RPCError(code: .dataLoss, message: "Error 3.", cause: unknownMerged)
    let abortedMerged = RPCError(
      code: .aborted,
      message: "Error 5. Error 4.",
      cause: dataLossMerged
    )
    #expect(error5 == abortedMerged)
  }

  @Test("Causes of errors with different status codes aren't flattened")
  func testDifferentStatusCodeAreNotFlattened() throws {
    let error1 = RPCError(code: .unknown, message: "Error 1.")
    let error2 = RPCError(code: .dataLoss, message: "Error 2.", cause: error1)
    let error3 = RPCError(code: .alreadyExists, message: "Error 3.", cause: error2)
    let error4 = RPCError(code: .aborted, message: "Error 4.", cause: error3)
    let error5 = RPCError(
      code: .deadlineExceeded,
      message: "Error 5.",
      cause: error4
    )

    #expect(error5.code == .deadlineExceeded)
    #expect(error5.message == "Error 5.")
    let wrappedError4 = try #require(error5.cause as? RPCError)
    #expect(wrappedError4.code == .aborted)
    #expect(wrappedError4.message == "Error 4.")
    let wrappedError3 = try #require(wrappedError4.cause as? RPCError)
    #expect(wrappedError3.code == .alreadyExists)
    #expect(wrappedError3.message == "Error 3.")
    let wrappedError2 = try #require(wrappedError3.cause as? RPCError)
    #expect(wrappedError2.code == .dataLoss)
    #expect(wrappedError2.message == "Error 2.")
    let wrappedError1 = try #require(wrappedError2.cause as? RPCError)
    #expect(wrappedError1.code == .unknown)
    #expect(wrappedError1.message == "Error 1.")
    #expect(wrappedError1.cause == nil)
  }

  @Test("Convert type to RPCError")
  func convertTypeUsingRPCErrorConvertible() {
    struct Cause: Error {}
    struct ConvertibleError: RPCErrorConvertible {
      var rpcErrorCode: RPCError.Code { .unknown }
      var rpcErrorMessage: String { "uhoh" }
      var rpcErrorMetadata: Metadata { ["k": "v"] }
      var rpcErrorCause: (any Error)? { Cause() }
    }

    let error = RPCError(ConvertibleError())
    #expect(error.code == .unknown)
    #expect(error.message == "uhoh")
    #expect(error.metadata == ["k": "v"])
    #expect(error.cause is Cause)
  }

  @Test("Convert type to RPCError with defaults")
  func convertTypeUsingRPCErrorConvertibleDefaults() {
    struct ConvertibleType: RPCErrorConvertible {
      var rpcErrorCode: RPCError.Code { .unknown }
      var rpcErrorMessage: String { "uhoh" }
    }

    let error = RPCError(ConvertibleType())
    #expect(error.code == .unknown)
    #expect(error.message == "uhoh")
    #expect(error.metadata == [:])
    #expect(error.cause == nil)
  }

  @Test("Convert error to RPCError with defaults")
  func convertErrorUsingRPCErrorConvertibleDefaults() {
    struct ConvertibleType: RPCErrorConvertible, Error {
      var rpcErrorCode: RPCError.Code { .unknown }
      var rpcErrorMessage: String { "uhoh" }
    }

    let error = RPCError(ConvertibleType())
    #expect(error.code == .unknown)
    #expect(error.message == "uhoh")
    #expect(error.metadata == [:])
    #expect(error.cause is ConvertibleType)
  }
}
