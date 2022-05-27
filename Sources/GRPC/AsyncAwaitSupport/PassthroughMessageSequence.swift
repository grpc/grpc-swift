/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.6)

/// An ``AsyncSequence`` adapter for a ``PassthroughMessageSource``.`
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal struct PassthroughMessageSequence<Element, Failure: Error>: AsyncSequence {
  @usableFromInline
  internal typealias Element = Element

  @usableFromInline
  internal typealias AsyncIterator = Iterator

  /// The source of messages in the sequence.
  @usableFromInline
  internal let _source: PassthroughMessageSource<Element, Failure>

  @usableFromInline
  internal func makeAsyncIterator() -> Iterator {
    return Iterator(storage: self._source)
  }

  @usableFromInline
  internal init(consuming source: PassthroughMessageSource<Element, Failure>) {
    self._source = source
  }

  @usableFromInline
  internal struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    internal let _storage: PassthroughMessageSource<Element, Failure>

    fileprivate init(storage: PassthroughMessageSource<Element, Failure>) {
      self._storage = storage
    }

    @inlinable
    internal func next() async throws -> Element? {
      // The storage handles co-operative cancellation, so we don't bother checking here.
      return try await self._storage.consumeNextElement()
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PassthroughMessageSequence: Sendable where Element: Sendable {}
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PassthroughMessageSequence.Iterator: Sendable where Element: Sendable {}

#endif // compiler(>=5.6)
