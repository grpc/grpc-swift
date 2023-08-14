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
@testable import GRPC
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import XCTest

struct UnwrapError: Error {}

// We support Swift versions before 'XCTUnwrap' was introduced.
func assertNotNil<Value>(
  _ expression: @autoclosure () throws -> Value?,
  message: @autoclosure () -> String = "Optional value was nil",
  file: StaticString = #filePath,
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
  file: StaticString = #filePath,
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

// The Swift 5.2 compiler will crash when trying to
// inline this function if the tests are running in
// release mode.
@inline(never)
func assertThat<Value>(
  _ expression: @autoclosure @escaping () throws -> Value,
  _ matcher: Matcher<Value>,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  // For value matchers we'll assert that we don't throw by default.
  assertThat(try expression(), .doesNotThrow(matcher), file: file, line: line)
}

func assertThat<Value>(
  _ expression: @autoclosure @escaping () throws -> Value,
  _ matcher: ExpressionMatcher<Value>,
  file: StaticString = #filePath,
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
  fileprivate typealias Evaluator = (Value) -> MatchResult
  private var matcher: Evaluator

  fileprivate init(_ matcher: @escaping Evaluator) {
    self.matcher = matcher
  }

  fileprivate func evaluate(_ value: Value) -> MatchResult {
    return self.matcher(value)
  }

  // MARK: Sugar

  /// Just returns the provided matcher.
  static func `is`<V>(_ matcher: Matcher<V>) -> Matcher<V> {
    return matcher
  }

  /// Just returns the provided matcher.
  static func and<V>(_ matcher: Matcher<V>) -> Matcher<V> {
    return matcher
  }

  // MARK: Equality

  /// Checks the equality of the actual value against the provided value. See `equalTo(_:)`.
  static func `is`<V: Equatable>(_ value: V) -> Matcher<V> {
    return .equalTo(value)
  }

  /// Checks the equality of the actual value against the provided value.
  static func equalTo<V: Equatable>(_ expected: V) -> Matcher<V> {
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

  /// Matches if the value is `nil`.
  static func none<V>() -> Matcher<V?> {
    return .init { actual in
      actual == nil
        ? .match
        : .noMatch(actual: String(describing: actual), expected: "nil")
    }
  }

  /// Matches if the value is not `nil`.
  static func some<V>(_ matcher: Matcher<V>? = nil) -> Matcher<V?> {
    return .init { actual in
      if let actual = actual {
        return matcher?.evaluate(actual) ?? .match
      } else {
        return .noMatch(actual: "nil", expected: "not nil")
      }
    }
  }

  // MARK: Result

  static func success<V>(_ matcher: Matcher<V>? = nil) -> Matcher<Result<V, Error>> {
    return .init { actual in
      switch actual {
      case let .success(value):
        return matcher?.evaluate(value) ?? .match
      case let .failure(error):
        return .noMatch(actual: "\(error)", expected: "success")
      }
    }
  }

  static func success() -> Matcher<Result<Void, Error>> {
    return .init { actual in
      switch actual {
      case .success:
        return .match
      case let .failure(error):
        return .noMatch(actual: "\(error)", expected: "success")
      }
    }
  }

  static func failure<Success, Failure: Error>(
    _ matcher: Matcher<Failure>? = nil
  ) -> Matcher<Result<Success, Failure>> {
    return .init { actual in
      switch actual {
      case let .success(value):
        return .noMatch(actual: "\(value)", expected: "failure")
      case let .failure(error):
        return matcher?.evaluate(error) ?? .match
      }
    }
  }

  // MARK: Utility

  static func all<V>(_ matchers: Matcher<V>...) -> Matcher<V> {
    return .init { actual in
      for matcher in matchers {
        let result = matcher.evaluate(actual)
        switch result {
        case .noMatch:
          return result
        case .match:
          ()
        }
      }
      return .match
    }
  }

  // MARK: Type

  /// Checks that the actual value is an instance of the given type.
  static func instanceOf<V, Expected>(_: Expected.Type) -> Matcher<V> {
    return .init { actual in
      if actual is Expected {
        return .match
      } else {
        return .noMatch(
          actual: String(describing: type(of: actual)) + " (\(actual))",
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
        : .noMatch(actual: "has count \(actual.count)", expected: "count of \(count)")
    }
  }

  static func isEmpty<C: Collection>() -> Matcher<C> {
    return .init { actual in
      actual.isEmpty
        ? .match
        : .noMatch(actual: "has \(actual.count) items", expected: "is empty")
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

  static func metadata<Request>(
    _ matcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<GRPCServerRequestPart<Request>> {
    return .init { actual in
      switch actual {
      case let .metadata(headers):
        return matcher?.evaluate(headers) ?? .match
      default:
        return .noMatch(actual: String(describing: actual), expected: "metadata")
      }
    }
  }

  static func message<Request>(
    _ matcher: Matcher<Request>? = nil
  ) -> Matcher<GRPCServerRequestPart<Request>> {
    return .init { actual in
      switch actual {
      case let .message(message):
        return matcher?.evaluate(message) ?? .match
      default:
        return .noMatch(actual: String(describing: actual), expected: "message")
      }
    }
  }

  static func metadata<Response>(
    _ matcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<GRPCServerResponsePart<Response>> {
    return .init { actual in
      switch actual {
      case let .metadata(headers):
        return matcher?.evaluate(headers) ?? .match
      default:
        return .noMatch(actual: String(describing: actual), expected: "metadata")
      }
    }
  }

  static func message<Response>(
    _ matcher: Matcher<Response>? = nil
  ) -> Matcher<GRPCServerResponsePart<Response>> {
    return .init { actual in
      switch actual {
      case let .message(message, _):
        return matcher?.evaluate(message) ?? .match
      default:
        return .noMatch(actual: String(describing: actual), expected: "message")
      }
    }
  }

  static func end<Response>(
    status statusMatcher: Matcher<GRPCStatus>? = nil,
    trailers trailersMatcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<GRPCServerResponsePart<Response>> {
    return .init { actual in
      switch actual {
      case let .end(status, trailers):
        let statusMatch = (statusMatcher?.evaluate(status) ?? .match)
        switch statusMatcher?.evaluate(status) ?? .match {
        case .match:
          return trailersMatcher?.evaluate(trailers) ?? .match
        case .noMatch:
          return statusMatch
        }
      default:
        return .noMatch(actual: String(describing: actual), expected: "end")
      }
    }
  }

  static func sendTrailers(
    _ matcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<HTTP2ToRawGRPCStateMachine.SendEndAction> {
    return .init { actual in
      switch actual {
      case let .sendTrailers(trailers):
        return matcher?.evaluate(trailers) ?? .match
      case .sendTrailersAndFinish:
        return .noMatch(actual: "sendTrailersAndFinish", expected: "sendTrailers")
      case let .failure(error):
        return .noMatch(actual: "\(error)", expected: "sendTrailers")
      }
    }
  }

  static func sendTrailersAndFinish(
    _ matcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<HTTP2ToRawGRPCStateMachine.SendEndAction> {
    return .init { actual in
      switch actual {
      case let .sendTrailersAndFinish(trailers):
        return matcher?.evaluate(trailers) ?? .match
      case .sendTrailers:
        return .noMatch(actual: "sendTrailers", expected: "sendTrailersAndFinish")
      case let .failure(error):
        return .noMatch(actual: "\(error)", expected: "sendTrailersAndFinish")
      }
    }
  }

  static func failure(
    _ matcher: Matcher<Error>? = nil
  ) -> Matcher<HTTP2ToRawGRPCStateMachine.SendEndAction> {
    return .init { actual in
      switch actual {
      case .sendTrailers:
        return .noMatch(actual: "sendTrailers", expected: "failure")
      case .sendTrailersAndFinish:
        return .noMatch(actual: "sendTrailersAndFinish", expected: "failure")
      case let .failure(error):
        return matcher?.evaluate(error) ?? .match
      }
    }
  }

  // MARK: HTTP/1

  static func head(
    status: HTTPResponseStatus,
    headers: HTTPHeaders? = nil
  ) -> Matcher<HTTPServerResponsePart> {
    return .init { actual in
      switch actual {
      case let .head(head):
        let statusMatches = Matcher.is(status).evaluate(head.status)
        switch statusMatches {
        case .match:
          return headers.map { Matcher.is($0).evaluate(head.headers) } ?? .match
        case .noMatch:
          return statusMatches
        }

      case .body, .end:
        return .noMatch(actual: "\(actual)", expected: "head")
      }
    }
  }

  static func body(_ matcher: Matcher<ByteBuffer>? = nil) -> Matcher<HTTPServerResponsePart> {
    return .init { actual in
      switch actual {
      case let .body(.byteBuffer(buffer)):
        return matcher.map { $0.evaluate(buffer) } ?? .match
      default:
        return .noMatch(actual: "\(actual)", expected: "body")
      }
    }
  }

  static func end() -> Matcher<HTTPServerResponsePart> {
    return .init { actual in
      switch actual {
      case .end:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "end")
      }
    }
  }

  // MARK: HTTP/2

  static func contains(
    _ name: String,
    _ values: [String]? = nil
  ) -> Matcher<HPACKHeaders> {
    return .init { actual in
      let headers = actual[canonicalForm: name]

      if headers.isEmpty {
        return .noMatch(actual: "does not contain '\(name)'", expected: "contains '\(name)'")
      } else {
        return values.map { Matcher.equalTo($0).evaluate(headers) } ?? .match
      }
    }
  }

  static func contains(
    caseSensitive caseSensitiveName: String
  ) -> Matcher<HPACKHeaders> {
    return .init { actual in
      for (name, _, _) in actual {
        if name == caseSensitiveName {
          return .match
        }
      }

      return .noMatch(
        actual: "does not contain '\(caseSensitiveName)'",
        expected: "contains '\(caseSensitiveName)'"
      )
    }
  }

  static func headers(
    _ headers: Matcher<HPACKHeaders>? = nil,
    endStream: Bool? = nil
  ) -> Matcher<HTTP2Frame.FramePayload> {
    return .init { actual in
      switch actual {
      case let .headers(payload):
        let headersMatch = headers?.evaluate(payload.headers)

        switch headersMatch {
        case .none,
             .some(.match):
          return endStream.map { Matcher.is($0).evaluate(payload.endStream) } ?? .match
        case .some(.noMatch):
          return headersMatch!
        }
      default:
        return .noMatch(actual: "\(actual)", expected: "headers")
      }
    }
  }

  static func data(
    buffer: ByteBuffer? = nil,
    endStream: Bool? = nil
  ) -> Matcher<HTTP2Frame.FramePayload> {
    return .init { actual in
      switch actual {
      case let .data(payload):
        let endStreamMatches = endStream.map { Matcher.is($0).evaluate(payload.endStream) }

        switch (endStreamMatches, payload.data) {
        case let (.none, .byteBuffer(b)),
             let (.some(.match), .byteBuffer(b)):
          return buffer.map { Matcher.is($0).evaluate(b) } ?? .match

        case (.some(.noMatch), .byteBuffer):
          return endStreamMatches!

        case (_, .fileRegion):
          preconditionFailure("Unexpected IOData.fileRegion")
        }

      default:
        return .noMatch(actual: "\(actual)", expected: "data")
      }
    }
  }

  static func trailersOnly(
    code: GRPCStatus.Code,
    contentType: String = "application/grpc"
  ) -> Matcher<HPACKHeaders> {
    return .all(
      .contains(":status", ["200"]),
      .contains("content-type", [contentType]),
      .contains("grpc-status", ["\(code.rawValue)"])
    )
  }

  static func trailers(code: GRPCStatus.Code, message: String) -> Matcher<HPACKHeaders> {
    return .all(
      .contains("grpc-status", ["\(code.rawValue)"]),
      .contains("grpc-message", [message])
    )
  }

  // MARK: HTTP2ToRawGRPCStateMachine.Action

  static func errorCaught() -> Matcher<HTTP2ToRawGRPCStateMachine.ReadNextMessageAction> {
    return .init { actual in
      switch actual {
      case .errorCaught:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "errorCaught")
      }
    }
  }

  static func configure() -> Matcher<HTTP2ToRawGRPCStateMachine.ReceiveHeadersAction> {
    return .init { actual in
      switch actual {
      case .configure:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "configurePipeline")
      }
    }
  }

  static func rejectRPC(
    _ matcher: Matcher<HPACKHeaders>? = nil
  ) -> Matcher<HTTP2ToRawGRPCStateMachine.ReceiveHeadersAction> {
    return .init { actual in
      switch actual {
      case let .rejectRPC(headers):
        return matcher?.evaluate(headers) ?? .match
      default:
        return .noMatch(actual: "\(actual)", expected: "rejectRPC")
      }
    }
  }

  static func forwardHeaders() -> Matcher<HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction> {
    return .init { actual in
      switch actual {
      case .forwardHeaders:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "forwardHeaders")
      }
    }
  }

  static func none() -> Matcher<HTTP2ToRawGRPCStateMachine.ReadNextMessageAction> {
    return .init { actual in
      switch actual {
      case .none:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "none")
      }
    }
  }

  static func forwardMessage() -> Matcher<HTTP2ToRawGRPCStateMachine.ReadNextMessageAction> {
    return .init { actual in
      switch actual {
      case .forwardMessage:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "forwardMessage")
      }
    }
  }

  static func forwardEnd() -> Matcher<HTTP2ToRawGRPCStateMachine.ReadNextMessageAction> {
    return .init { actual in
      switch actual {
      case .forwardEnd:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "forwardEnd")
      }
    }
  }

  static func forwardHeadersThenRead()
    -> Matcher<HTTP2ToRawGRPCStateMachine.PipelineConfiguredAction> {
    return .init { actual in
      switch actual {
      case .forwardHeadersAndRead:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "forwardHeadersAndRead")
      }
    }
  }

  static func forwardMessageThenRead()
    -> Matcher<HTTP2ToRawGRPCStateMachine.ReadNextMessageAction> {
    return .init { actual in
      switch actual {
      case .forwardMessageThenReadNextMessage:
        return .match
      default:
        return .noMatch(actual: "\(actual)", expected: "forwardMessageThenReadNextMessage")
      }
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
  static func doesNotThrow<V>(_ matcher: Matcher<V>? = nil) -> ExpressionMatcher<V> {
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
  static func `throws`<V>(_ matcher: Matcher<Error>? = nil) -> ExpressionMatcher<V> {
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

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
func assertThat<Value>(
  _ expression: @autoclosure @escaping () async throws -> Value,
  _ matcher: Matcher<Value>,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  // For value matchers we'll assert that we don't throw by default.
  await assertThat(try await expression(), .doesNotThrow(matcher), file: file, line: line)
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
func assertThat<Value>(
  _ expression: @autoclosure @escaping () async throws -> Value,
  _ matcher: ExpressionMatcher<Value>,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  // Create a shim here from async-await world...
  let result: Result<Value, Error>
  do {
    let value = try await expression()
    result = .success(value)
  } catch {
    result = .failure(error)
  }
  switch matcher.evaluate(result.get) {
  case .match:
    ()
  case let .noMatch(actual: actual, expected: expected):
    XCTFail("ACTUAL: \(actual), EXPECTED: \(expected)", file: file, line: line)
  }
}
