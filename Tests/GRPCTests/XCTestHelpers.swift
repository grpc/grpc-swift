/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import GRPC
import XCTest

struct UnwrapError: Error {}

// We support Swift versions before 'XCTUnwrap' was introduced.
func assertNotNil<Value>(
  _ expression: @autoclosure () throws -> Value?,
  message: @autoclosure () -> String = "Optional value was nil",
  file: StaticString = #file,
  line: UInt = #line
) throws -> Value {
  guard let value = try expression() else {
    XCTFail(message(), file: file, line: line)
    throw UnwrapError()
  }
  return value
}

func assertNoThrow<Value>(
  _ expression: @autoclosure () throws -> Value,
  message: @autoclosure () -> String = "Unexpected error thrown",
  file: StaticString = #file,
  line: UInt = #line
) throws -> Value {
  do {
    return try expression()
  } catch {
    XCTFail(message(), file: file, line: line)
    throw error
  }
}

// MARK: - Matchers.

func assertThat<Value>(
  _ expression: @autoclosure @escaping () throws -> Value,
  _ matcher: Matcher<Value>,
  file: StaticString = #file,
  line: UInt = #line
) {
  // For value matchers we'll assert that we don't throw by default.
  assertThat(try expression(), .doesNotThrow(matcher), file: file, line: line)
}

func assertThat<Value>(
  _ expression: @autoclosure @escaping () throws -> Value,
  _ matcher: ExpressionMatcher<Value>,
  file: StaticString = #file,
  line: UInt = #line
) {
  switch matcher.evaluate(expression) {
  case .match:
    ()
  case let .noMatch(actual: actual, expected: expected):
    XCTFail("ACTUAL: \(actual), EXPECTED: \(expected)", file: file, line: line)
  }
}

enum MatchResult {
  case match
  case noMatch(actual: String, expected: String)
}

struct Matcher<Value> {
  private typealias Evaluator = (Value) -> MatchResult
  private var matcher: Evaluator

  private init(_ matcher: @escaping Evaluator) {
    self.matcher = matcher
  }

  fileprivate func evaluate(_ value: Value) -> MatchResult {
    return self.matcher(value)
  }

  // MARK: Sugar

  /// Just returns the provided matcher.
  static func `is`<Value>(_ matcher: Matcher<Value>) -> Matcher<Value> {
    return matcher
  }

  /// Just returns the provided matcher.
  static func and<Value>(_ matcher: Matcher<Value>) -> Matcher<Value> {
    return matcher
  }

  // MARK: Equality

  /// Checks the equality of the actual value against the provided value. See `equalTo(_:)`.
  static func `is`<Value: Equatable>(_ value: Value) -> Matcher<Value> {
    return .equalTo(value)
  }

  /// Checks the equality of the actual value against the provided value.
  static func equalTo<Value: Equatable>(_ expected: Value) -> Matcher<Value> {
    return .init { actual in
      actual == expected
        ? .match
        : .noMatch(actual: "\(actual)", expected: "equal to \(expected)")
    }
  }

  /// Always returns a 'match', useful when the expected value is `Void`.
  static func isVoid() -> Matcher<Void> {
    return .init {
      return .match
    }
  }

  // MARK: Type

  /// Checks that the actual value is an instance of the given type.
  static func instanceOf<Value, Expected>(_: Expected.Type) -> Matcher<Value> {
    return .init { actual in
      if actual is Expected {
        return .match
      } else {
        return .noMatch(
          actual: String(describing: type(of: actual)),
          expected: "value of type \(Expected.self)"
        )
      }
    }
  }

  // MARK: Collection

  /// Checks whether the collection has the expected count.
  static func hasCount<C: Collection>(_ count: Int) -> Matcher<C> {
    return .init { actual in
      actual.count == count
        ? .match
        : .noMatch(actual: "has count \(actual)", expected: "count of \(count)")
    }
  }

  // MARK: gRPC matchers

  static func hasCode(_ code: GRPCStatus.Code) -> Matcher<GRPCStatus> {
    return .init { actual in
      actual.code == code
        ? .match
        : .noMatch(actual: "has status code \(actual)", expected: "\(code)")
    }
  }
}

struct ExpressionMatcher<Value> {
  typealias Expression = () throws -> Value
  private typealias Evaluator = (Expression) -> MatchResult
  private var evaluator: Evaluator

  private init(_ evaluator: @escaping Evaluator) {
    self.evaluator = evaluator
  }

  fileprivate func evaluate(_ expression: Expression) -> MatchResult {
    return self.evaluator(expression)
  }

  /// Asserts that the expression does not throw and error. Returns the result of any provided
  /// matcher on the result of the expression.
  static func doesNotThrow<Value>(_ matcher: Matcher<Value>? = nil) -> ExpressionMatcher<Value> {
    return .init { expression in
      do {
        let value = try expression()
        return matcher?.evaluate(value) ?? .match
      } catch {
        return .noMatch(actual: "threw '\(error)'", expected: "should not throw error")
      }
    }
  }

  /// Asserts that the expression throws and error. Returns the result of any provided matcher
  /// on the error thrown by the expression.
  static func `throws`<Value>(_ matcher: Matcher<Error>? = nil) -> ExpressionMatcher<Value> {
    return .init { expression in
      do {
        let value = try expression()
        return .noMatch(actual: "returned '\(value)'", expected: "should throw error")
      } catch {
        return matcher?.evaluate(error) ?? .match
      }
    }
  }
}
