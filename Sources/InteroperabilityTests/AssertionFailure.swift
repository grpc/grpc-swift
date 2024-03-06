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

/// Failure assertion for interoperability testing.
///
/// This is required because the tests must be able to run without XCTest.
public struct AssertionFailure: Error {
  public var message: String
  public var file: String
  public var line: Int

  public init(message: String, file: String = #fileID, line: Int = #line) {
    self.message = message
    self.file = file
    self.line = line
  }
}

/// Asserts that the value of an expression is `true`.
public func assertTrue(
  _ expression: @autoclosure () throws -> Bool,
  _ message: String = "The statement is not true.",
  file: String = #fileID,
  line: Int = #line
) throws {
  guard try expression() else {
    throw AssertionFailure(message: message, file: file, line: line)
  }
}

/// Asserts that the two given values are equal.
public func assertEqual<T: Equatable>(
  _ value1: T,
  _ value2: T,
  file: String = #fileID,
  line: Int = #line
) throws {
  return try assertTrue(
    value1 == value2,
    "'\(value1)' is not equal to '\(value2)'",
    file: file,
    line: line
  )
}
