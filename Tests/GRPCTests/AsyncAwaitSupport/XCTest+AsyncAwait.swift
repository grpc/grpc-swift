/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.5)
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  verify: (Error) -> Void = { _ in },
  file: StaticString = #file,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expression did not throw error", file: file, line: line)
  } catch {
    verify(error)
  }
}

#endif // compiler(>=5.5)
