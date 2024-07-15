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

/// A type-erasing `AsyncSequence`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct RPCAsyncSequence<Element, Failure: Error>: AsyncSequence, Sendable {
  // Need a typealias: https://github.com/swiftlang/swift/issues/63877
  @usableFromInline
  typealias Wrapped = AsyncSequence<Element, Failure> & Sendable

  @usableFromInline
  let _wrapped: any Wrapped

  /// Creates an ``RPCAsyncSequence`` by wrapping another `AsyncSequence`.
  public init<Source: AsyncSequence<Element, Failure>>(
    wrapping other: Source
  ) where Source: Sendable {
    self._wrapped = other
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(wrapping: self._wrapped.makeAsyncIterator())
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: any AsyncIteratorProtocol<Element, Failure>

    fileprivate init(
      wrapping other: some AsyncIteratorProtocol<Element, Failure>
    ) {
      self.iterator = other
    }

    public mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(Failure) -> Element? {
      try await self.iterator.next(isolation: `actor`)
    }

    public mutating func next() async throws -> Element? {
      try await self.next(isolation: nil)
    }
  }
}

@available(*, unavailable)
extension RPCAsyncSequence.AsyncIterator: Sendable {}
