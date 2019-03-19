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
import Foundation
import XCTest
import SwiftGRPCNIO
import SwiftGRPCNIOSampleCerts
import NIO
import NIOHTTP1
import SwiftProtobuf

// Assert the given expression does not throw, and validate the return value from that expression.
public func XCTAssertNoThrow<T>(
  _ expression: @autoclosure () throws -> T,
  _ message: String = "",
  file: StaticString = #file,
  line: UInt = #line,
  validate: (T) -> Void
) {
  var value: T? = nil
  XCTAssertNoThrow(try value = expression(), message, file: file, line: line)
  value.map { validate($0) }
}

struct CaseExtractError: Error {
  let message: String
}

@discardableResult
func extractHeaders(_ response: RawGRPCServerResponsePart) throws -> HTTPHeaders {
  guard case .headers(let headers) = response else {
    throw CaseExtractError(message: "\(response) did not match .headers")
  }
  return headers
}

@discardableResult
func extractMessage(_ response: RawGRPCServerResponsePart) throws -> Data {
  guard case .message(let message) = response else {
    throw CaseExtractError(message: "\(response) did not match .message")
  }
  return message
}

@discardableResult
func extractStatus(_ response: RawGRPCServerResponsePart) throws -> GRPCStatus {
  guard case .status(let status) = response else {
    throw CaseExtractError(message: "\(response) did not match .status")
  }
  return status
}

extension GRPCSwiftCertificate {
  func assertNotExpired(file: StaticString = #file, line: UInt = #line) {
    XCTAssertFalse(self.isExpired, "Certificate expired at \(self.notAfter)", file: file, line: line)
  }
}

func expectStatusCode(_ expected: StatusCode, for status: EventLoopFuture<GRPCStatus>, fulfill expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) {
  status.whenComplete { result in
    switch result {
    case .success(let actual):
      XCTAssertEqual(expected, actual.code, file: file, line: line)

    case .failure(let error):
      XCTFail("Unexpectedly failed with error: \(error)", file: file, line: line)
    }
    expectation?.fulfill()
  }
}

func expectResponse<ResponseMessage: Message & Equatable>(_ expected: ResponseMessage, for response: EventLoopFuture<ResponseMessage>, fulfill expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) {
  response.whenComplete { result in
    switch result {
    case .success(let actual):
      XCTAssertEqual(expected, actual, file: file, line: line)

    case .failure(let error):
      XCTFail("Unexpectedly failed with error: \(error)", file: file, line: line)
    }
    expectation?.fulfill()
  }
}

func assertResponse(_ expected: Echo_EchoResponse, actual: Echo_EchoResponse, fulfill expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) {
  XCTAssertEqual(expected, actual, file: file, line: line)
  expectation?.fulfill()
}


extension UnaryResponseClientCall where ResponseMessage: Equatable {
  func expectResponse(_ expected: ResponseMessage, fulfill expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) {
    SwiftGRPCNIOTests.expectResponse(expected, for: self.response, fulfill: expectation, file: file, line: line)
  }
}

extension ClientCall {
  func expectStatusCode(_ expecteded: StatusCode, fulfill expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) {
    SwiftGRPCNIOTests.expectStatusCode(expecteded, for: self.status, fulfill: expectation, file: file, line: line)
  }
}
