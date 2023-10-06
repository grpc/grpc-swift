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

func XCTAssertDescription(
  _ subject: some CustomStringConvertible,
  _ expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(String(describing: subject), expected, file: file, line: line)
}

func XCTAssertThrowsRPCError<T>(
  _ expression: @autoclosure () throws -> T,
  _ errorHandler: (RPCError) -> Void
) {
  XCTAssertThrowsError(try expression()) { error in
    guard let error = error as? RPCError else {
      return XCTFail("Error had unexpected type '\(type(of: error))'")
    }

    errorHandler(error)
  }
}

func XCTAssertThrowsRPCErrorAsync<T>(
  _ expression: () async throws -> T,
  errorHandler: (RPCError) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expression didn't throw")
  } catch let error as RPCError {
    errorHandler(error)
  } catch {
    XCTFail("Error had unexpected type '\(type(of: error))'")
  }
}
