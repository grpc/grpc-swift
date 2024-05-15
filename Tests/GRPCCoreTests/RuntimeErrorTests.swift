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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class RuntimeErrorTests: XCTestCase {
  func testCopyOnWrite() {
    // RuntimeError has a heap based storage, so check CoW semantics are correctly implemented.
    let error1 = RuntimeError(code: .transportError, message: "Failed to start transport")
    var error2 = error1
    error2.code = .serverIsAlreadyRunning
    XCTAssertEqual(error1.code, .transportError)
    XCTAssertEqual(error2.code, .serverIsAlreadyRunning)

    var error3 = error1
    error3.message = "foo"
    XCTAssertEqual(error1.message, "Failed to start transport")
    XCTAssertEqual(error3.message, "foo")

    var error4 = error1
    error4.cause = CancellationError()
    XCTAssertNil(error1.cause)
    XCTAssert(error4.cause is CancellationError)
  }

  func testCustomStringConvertible() {
    let error1 = RuntimeError(code: .transportError, message: "Failed to start transport")
    XCTAssertDescription(error1, #"transportError: "Failed to start transport""#)

    let error2 = RuntimeError(
      code: .transportError,
      message: "Failed to start transport",
      cause: CancellationError()
    )
    XCTAssertDescription(
      error2,
      #"transportError: "Failed to start transport" (cause: "CancellationError()")"#
    )
  }
}
