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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class ResultCatchingTests: XCTestCase {
  func testResultCatching() async {
    let result = await Result {
      try? await Task.sleep(nanoseconds: 1)
      throw RPCError(code: .unknown, message: "foo")
    }

    switch result {
    case .success:
      XCTFail()
    case .failure(let error):
      XCTAssertEqual(error as? RPCError, RPCError(code: .unknown, message: "foo"))
    }
  }

  func testCastToErrorOfCorrectType() async {
    let result = Result<Void, any Error>.failure(RPCError(code: .unknown, message: "foo"))
    let typedFailure = result.castError(to: RPCError.self) { _ in
      XCTFail("buildError(_:) was called")
      return RPCError(code: .failedPrecondition, message: "shouldn't happen")
    }

    switch typedFailure {
    case .success:
      XCTFail()
    case .failure(let error):
      XCTAssertEqual(error, RPCError(code: .unknown, message: "foo"))
    }
  }

  func testCastToErrorOfIncorrectType() async {
    struct WrongError: Error {}
    let result = Result<Void, any Error>.failure(WrongError())
    let typedFailure = result.castError(to: RPCError.self) { _ in
      return RPCError(code: .invalidArgument, message: "fallback")
    }

    switch typedFailure {
    case .success:
      XCTFail()
    case .failure(let error):
      XCTAssertEqual(error, RPCError(code: .invalidArgument, message: "fallback"))
    }
  }
}
