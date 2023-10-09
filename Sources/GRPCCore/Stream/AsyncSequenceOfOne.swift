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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RPCAsyncSequence {
  /// Returns an ``RPCAsyncSequence`` containing just the given element.
  @_spi(Testing)
  public static func one(_ element: Element) -> Self {
    return Self(wrapping: AsyncSequenceOfOne<Element, Never>(result: .success(element)))
  }

  /// Returns an ``RPCAsyncSequence`` throwing the given error.
  @_spi(Testing)
  public static func throwing<E: Error>(_ error: E) -> Self {
    return Self(wrapping: AsyncSequenceOfOne<Element, E>(result: .failure(error)))
  }
}

/// An `AsyncSequence` of a single value.
private struct AsyncSequenceOfOne<Element: Sendable, Failure: Error>: AsyncSequence {
  private let result: Result<Element, Failure>

  init(result: Result<Element, Failure>) {
    self.result = result
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(result: self.result)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private var result: Result<Element, Failure>?

    fileprivate init(result: Result<Element, Failure>) {
      self.result = result
    }

    mutating func next() async throws -> Element? {
      guard let result = self.result else { return nil }

      self.result = nil
      return try result.get()
    }
  }
}
