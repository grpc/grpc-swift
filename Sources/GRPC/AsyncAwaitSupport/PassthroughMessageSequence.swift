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
#if compiler(>=5.5)

/// An ``AsyncSequence`` adapter for a ``PassthroughMessageSource``.`
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
internal struct PassthroughMessageSequence<Element, Failure: Error>: AsyncSequence {
  internal typealias Element = Element
  internal typealias AsyncIterator = Iterator

  /// The source of messages in the sequence.
  private let source: PassthroughMessageSource<Element, Failure>

  internal func makeAsyncIterator() -> Iterator {
    return Iterator(storage: self.source)
  }

  internal init(consuming source: PassthroughMessageSource<Element, Failure>) {
    self.source = source
  }

  internal struct Iterator: AsyncIteratorProtocol {
    private let storage: PassthroughMessageSource<Element, Failure>

    fileprivate init(storage: PassthroughMessageSource<Element, Failure>) {
      self.storage = storage
    }

    internal func next() async throws -> Element? {
      return try await self.storage.consumeNextElement()
    }
  }
}

#endif // compiler(>=5.5)
