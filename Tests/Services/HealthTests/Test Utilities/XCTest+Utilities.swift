/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

func XCTAssertThrowsError<T, E: Error>(
  ofType: E.Type,
  _ expression: @autoclosure () throws -> T,
  _ errorHandler: (E) -> Void
) {
  XCTAssertThrowsError(try expression()) { error in
    guard let error = error as? E else {
      return XCTFail("Error had unexpected type '\(type(of: error))'")
    }
    errorHandler(error)
  }
}
