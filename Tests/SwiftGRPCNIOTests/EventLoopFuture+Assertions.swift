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
import NIO
import XCTest

extension EventLoopFuture where Value: Equatable {
  /// Registers a callback which asserts the value promised by this future is equal to
  /// the expected value. Causes a test failure if the future returns an error.
  ///
  /// - Parameters:
  ///   - expected: The expected value.
  ///   - expectation: A test expectation to fulfill once the future has completed.
  func assertEqual(_ expected: Value, fulfill expectation: XCTestExpectation, file: StaticString = #file, line: UInt = #line) {
    self.whenComplete { result in
      defer {
        expectation.fulfill()
      }

      switch result {
      case .success(let actual):
        XCTAssertEqual(expected, actual, file: file, line: line)

      case .failure(let error):
        XCTFail("Expecteded '\(expected)' but received error: \(error)", file: file, line: line)
      }
    }
  }
}
