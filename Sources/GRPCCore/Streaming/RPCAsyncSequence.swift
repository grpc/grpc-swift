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
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct RPCAsyncSequence<Element>: AsyncSequence, Sendable {
  private let _makeAsyncIterator: @Sendable () -> AsyncIterator

  /// Creates an ``RPCAsyncSequence`` by wrapping another `AsyncSequence`.
  public init<S: AsyncSequence>(wrapping other: S) where S.Element == Element {
    self._makeAsyncIterator = {
      AsyncIterator(wrapping: other.makeAsyncIterator())
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    self._makeAsyncIterator()
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: any AsyncIteratorProtocol

    fileprivate init<Iterator>(
      wrapping other: Iterator
    ) where Iterator: AsyncIteratorProtocol, Iterator.Element == Element {
      self.iterator = other
    }

    public mutating func next() async throws -> Element? {
      let elem = try await self.iterator.next()
      return elem as? Element
    }
  }
}

@available(*, unavailable)
extension RPCAsyncSequence.AsyncIterator: Sendable {}
