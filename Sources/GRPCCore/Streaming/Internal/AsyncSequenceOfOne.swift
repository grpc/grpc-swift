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

@available(gRPCSwift 2.0, *)
extension RPCAsyncSequence {
  /// Returns an ``RPCAsyncSequence`` containing just the given element.
  @inlinable
  static func one(_ element: Element) -> Self {
    let source = AsyncSequenceOfOne<Element, Failure>(result: .success(element))
    return RPCAsyncSequence(wrapping: source)
  }

  /// Returns an ``RPCAsyncSequence`` throwing the given error.
  @inlinable
  static func throwing(_ error: Failure) -> Self {
    let source = AsyncSequenceOfOne<Element, Failure>(result: .failure(error))
    return RPCAsyncSequence(wrapping: source)
  }
}

/// An `AsyncSequence` of a single value.
@usableFromInline
@available(gRPCSwift 2.0, *)
struct AsyncSequenceOfOne<Element: Sendable, Failure: Error>: AsyncSequence, Sendable {
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
    mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(Failure) -> Element? {
      guard let result = self.result else { return nil }

      self.result = nil
      return try result.get()
    }

    @inlinable
    mutating func next() async throws -> Element? {
      try await self.next(isolation: nil)
    }
  }
}
