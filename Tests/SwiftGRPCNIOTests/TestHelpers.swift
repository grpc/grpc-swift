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
import NIO
import NIOHTTP1

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
func extractMessage(_ response: RawGRPCServerResponsePart) throws -> ByteBuffer {
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
