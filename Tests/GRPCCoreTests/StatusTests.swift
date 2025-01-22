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

@Suite("Status")
struct StatusTests {
  @Suite("Code")
  struct Code {
    @Test("rawValue", arguments: zip(Status.Code.all, 0 ... 16))
    func rawValueOfStatusCodes(code: Status.Code, expected: Int) {
      #expect(code.rawValue == expected)
    }

    @Test(
      "Initialize from RPCError.Code",
      arguments: zip(
        RPCError.Code.all,
        Status.Code.all.dropFirst()  // Drop '.ok', there is no '.ok' error code.
      )
    )
    func initFromRPCErrorCode(errorCode: RPCError.Code, expected: Status.Code) {
      #expect(Status.Code(errorCode) == expected)
    }

    @Test("Initialize from rawValue", arguments: zip(0 ... 16, Status.Code.all))
    func initFromRawValue(rawValue: Int, expected: Status.Code) {
      #expect(Status.Code(rawValue: rawValue) == expected)
    }

    @Test("Initialize from invalid rawValue", arguments: [-1, 17, 100, .max])
    func initFromInvalidRawValue(rawValue: Int) {
      #expect(Status.Code(rawValue: rawValue) == nil)
    }
  }

  @Test("CustomStringConvertible conformance")
  func customStringConvertible() {
    #expect("\(Status(code: .ok, message: ""))" == #"ok: """#)
    #expect("\(Status(code: .dataLoss, message: "oh no"))" == #"dataLoss: "oh no""#)
  }

  @Test("Equatable conformance")
  func equatable() {
    let ok = Status(code: .ok, message: "")
    let okWithMessage = Status(code: .ok, message: "message")
    let internalError = Status(code: .internalError, message: "")

    #expect(ok == ok)
    #expect(ok != okWithMessage)
    #expect(ok != internalError)
  }

  @Test("Fits in existential container")
  func fitsInExistentialContainer() {
    #expect(MemoryLayout<Status>.size <= 24)
  }

  @Test(
    "From HTTP status code",
    arguments: [
      (400, Status(code: .internalError, message: "HTTP 400: Bad Request")),
      (401, Status(code: .unauthenticated, message: "HTTP 401: Unauthorized")),
      (403, Status(code: .permissionDenied, message: "HTTP 403: Forbidden")),
      (404, Status(code: .unimplemented, message: "HTTP 404: Not Found")),
      (429, Status(code: .unavailable, message: "HTTP 429: Too Many Requests")),
      (502, Status(code: .unavailable, message: "HTTP 502: Bad Gateway")),
      (503, Status(code: .unavailable, message: "HTTP 503: Service Unavailable")),
      (504, Status(code: .unavailable, message: "HTTP 504: Gateway Timeout")),
      (418, Status(code: .unknown, message: "HTTP 418")),
    ]
  )
  func convertFromHTTPStatusCode(code: Int, expected: Status) {
    let status = Status(httpStatusCode: code)
    #expect(status == expected)
  }
}
