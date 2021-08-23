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

extension XCTestCase {
  @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
  /// Cross-platform XCTest support for async-await tests.
  ///
  /// Currently the Linux implementation of XCTest doesn't have async-await support.
  /// Until it does, we make use of this shim which uses a detached `Task` along with
  /// `XCTest.wait(for:timeout:)` to wrap the operation.
  ///
  /// - NOTE: Support for Linux is tracked by https://bugs.swift.org/browse/SR-14403.
  /// - NOTE: Implementation currently in progress: https://github.com/apple/swift-corelibs-xctest/pull/326
  func XCTAsyncTest(
    expectationDescription: String = "Async operation",
    timeout: TimeInterval = 30,
    file: StaticString = #filePath,
    line: UInt = #line,
    function: StaticString = #function,
    operation: @escaping () async throws -> Void
  ) {
    let expectation = self.expectation(description: expectationDescription)
    Task {
      do {
        try await operation()
      } catch {
        XCTFail("Error thrown while executing \(function): \(error)", file: file, line: line)
        Thread.callStackSymbols.forEach { print($0) }
      }
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: timeout)
  }
}

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
