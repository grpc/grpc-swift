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
@available(gRPCSwift 2.0, *)
public struct RPCAsyncSequence<
  Element: Sendable,
  Failure: Error
>: AsyncSequence, @unchecked Sendable {
  // @unchecked Sendable is required because 'any' doesn't support composition with primary
  // associated types. (see: https://github.com/swiftlang/swift/issues/63877)
  //
  // To work around that limitation the 'init' requires that the async sequence being wrapped
  // is 'Sendable' but that constraint must be dropped internally. This is safe, the compiler just
  // can't prove it.
  @usableFromInline
  let _wrapped: any AsyncSequence<Element, Failure>

  /// Creates an ``RPCAsyncSequence`` by wrapping another `AsyncSequence`.
  @inlinable
  public init<Source: AsyncSequence<Element, Failure>>(
    wrapping other: Source
  ) where Source: Sendable {
    self._wrapped = other
  }

  @inlinable
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(wrapping: self._wrapped.makeAsyncIterator())
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    @usableFromInline
    private(set) var iterator: any AsyncIteratorProtocol<Element, Failure>

    @inlinable
    init(
      wrapping other: some AsyncIteratorProtocol<Element, Failure>
    ) {
      self.iterator = other
    }

    @inlinable
    public mutating func next(
      isolation actor: isolated (any Actor)?
    ) async throws(Failure) -> Element? {
      try await self.iterator.next(isolation: `actor`)
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      try await self.next(isolation: nil)
    }
  }
}

@available(*, unavailable)
extension RPCAsyncSequence.AsyncIterator: Sendable {}
