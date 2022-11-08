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
import NIOCore
import XCTest

extension EventLoopFuture where Value: Equatable {
  /// Registers a callback which asserts the value promised by this future is equal to
  /// the expected value. Causes a test failure if the future returns an error.
  ///
  /// - Parameters:
  ///   - expected: The expected value.
  ///   - expectation: A test expectation to fulfill once the future has completed.
  func assertEqual(
    _ expected: Value,
    fulfill expectation: XCTestExpectation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    self.whenComplete { result in
      defer {
        expectation.fulfill()
      }

      switch result {
      case let .success(actual):
        // swiftformat:disable:next redundantParens
        XCTAssertEqual(expected, actual, file: (file), line: line)

      case let .failure(error):
        // swiftformat:disable:next redundantParens
        XCTFail("Expecteded '\(expected)' but received error: \(error)", file: (file), line: line)
      }
    }
  }
}

extension EventLoopFuture {
  /// Registers a callback which asserts that this future is fulfilled with an error. Causes a test
  /// failure if the future is not fulfilled with an error.
  ///
  /// Callers can additionally verify the error by providing an error handler.
  ///
  /// - Parameters:
  ///   - expectation: A test expectation to fulfill once the future has completed.
  ///   - handler: A block to run additional verification on the error. Defaults to no-op.
  func assertError(
    fulfill expectation: XCTestExpectation,
    file: StaticString = #filePath,
    line: UInt = #line,
    handler: @escaping (Error) -> Void = { _ in }
  ) {
    self.whenComplete { result in
      defer {
        expectation.fulfill()
      }

      switch result {
      case .success:
        // swiftformat:disable:next redundantParens
        XCTFail("Unexpectedly received \(Value.self), expected an error", file: (file), line: line)

      case let .failure(error):
        handler(error)
      }
    }
  }

  /// Registers a callback which fulfills an expectation when the future succeeds.
  ///
  /// - Parameter expectation: The expectation to fulfill.
  func assertSuccess(
    fulfill expectation: XCTestExpectation,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    self.whenSuccess { _ in
      expectation.fulfill()
    }
  }
}

extension EventLoopFuture {
  // TODO: Replace with `always` once https://github.com/apple/swift-nio/pull/981 is released.
  func peekError(callback: @escaping (Error) -> Void) -> EventLoopFuture<Value> {
    self.whenFailure(callback)
    return self
  }

  // TODO: Replace with `always` once https://github.com/apple/swift-nio/pull/981 is released.
  func peek(callback: @escaping (Value) -> Void) -> EventLoopFuture<Value> {
    self.whenSuccess(callback)
    return self
  }
}
