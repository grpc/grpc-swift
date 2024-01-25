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
  @inlinable
  static func one(_ element: Element) -> Self {
    return Self(wrapping: AsyncSequenceOfOne<Element, Never>(result: .success(element)))
  }

  /// Returns an ``RPCAsyncSequence`` throwing the given error.
  @inlinable
  static func throwing<E: Error>(_ error: E) -> Self {
    return Self(wrapping: AsyncSequenceOfOne<Element, E>(result: .failure(error)))
  }
}

/// An `AsyncSequence` of a single value.
@usableFromInline
@available(macOS 10.15, iOS 13.0, tvOS 13, watchOS 6, *)
struct AsyncSequenceOfOne<Element: Sendable, Failure: Error>: AsyncSequence {
  @usableFromInline
  let result: Result<Element, Failure>

  @inlinable
  init(result: Result<Element, Failure>) {
    self.result = result
  }

  @inlinable
  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(result: self.result)
  }

  @usableFromInline
  struct AsyncIterator: AsyncIteratorProtocol {
    @usableFromInline
    private(set) var result: Result<Element, Failure>?

    @inlinable
    init(result: Result<Element, Failure>) {
      self.result = result
    }

    @inlinable
    mutating func next() async throws -> Element? {
      guard let result = self.result else { return nil }

      self.result = nil
      return try result.get()
    }
  }
}
