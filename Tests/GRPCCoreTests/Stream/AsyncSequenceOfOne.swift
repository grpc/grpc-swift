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
@_spi(Testing) import GRPCCore
import XCTest

internal final class AsyncSequenceOfOneTests: XCTestCase {
  func testSuccessPath() async throws {
    let sequence = RPCAsyncSequence.one("foo")
    let contents = try await sequence.collect()
    XCTAssertEqual(contents, ["foo"])
  }

  func testFailurePath() async throws {
    let sequence = RPCAsyncSequence<String>.throwing(RPCError(code: .cancelled, message: "foo"))

    do {
      let _ = try await sequence.collect()
      XCTFail("Expected an error to be thrown")
    } catch let error as RPCError {
      XCTAssertEqual(error.code, .cancelled)
      XCTAssertEqual(error.message, "foo")
    } catch {
      XCTFail("Expected error of type RPCError to be thrown")
    }
  }
}
