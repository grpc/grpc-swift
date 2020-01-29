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

/// Assertion error for interoperability testing.
///
/// This is required because these tests must be able to run without XCTest.
public struct AssertionError: Error {
  let message: String
  let file: StaticString
  let line: UInt
}

/// Asserts that the two given values are equal.
public func assertEqual<T: Equatable>(
  _ value1: T,
  _ value2: T,
  file: StaticString = #file,
  line: UInt = #line
) throws {
  guard value1 == value2 else {
    throw AssertionError(message: "'\(value1)' is not equal to '\(value2)'", file: file, line: line)
  }
}

/// Waits for the future to be fulfilled and asserts that its value is equal to the given value.
///
/// - Important: This should not be run on an event loop since this function calls `wait()` on the
///   given future.
public func waitAndAssertEqual<T: Equatable>(
  _ future: EventLoopFuture<T>,
  _ value: T,
  file: StaticString = #file,
  line: UInt = #line
) throws {
  try assertEqual(try future.wait(), value, file: file, line: line)
}

/// Waits for the futures to be fulfilled and ssserts that their values are equal.
///
/// - Important: This should not be run on an event loop since this function calls `wait()` on the
///   given future.
public func waitAndAssertEqual<T: Equatable>(
  _ future1: EventLoopFuture<T>,
  _ future2: EventLoopFuture<T>,
  file: StaticString = #file,
  line: UInt = #line
) throws {
  try assertEqual(try future1.wait(), try future2.wait(), file: file, line: line)
}

public func waitAndAssert<T>(
  _ future: EventLoopFuture<T>,
  file: StaticString = #file,
  line: UInt = #line,
  message: String = "",
  verify: (T) -> Bool
) throws {
  let value = try future.wait()
  guard verify(value) else {
    throw AssertionError(message: message, file: file, line: line)
  }
}
