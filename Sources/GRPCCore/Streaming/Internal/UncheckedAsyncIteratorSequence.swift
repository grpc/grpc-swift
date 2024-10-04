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

public import Synchronization  // should be @usableFromInline

@usableFromInline
/// An `AsyncSequence` which wraps an existing async iterator.
final class UncheckedAsyncIteratorSequence<
  Base: AsyncIteratorProtocol
>: AsyncSequence, @unchecked Sendable {
  // This is '@unchecked Sendable' because iterators are typically marked as not being Sendable
  // to avoid multiple iterators being created. This is done to avoid multiple concurrent consumers
  // of a single async sequence.
  //
  // However, gRPC needs to read the first message in a sequence of inbound request/response parts
  // to check how the RPC should be handled. To do this it creates an async iterator and waits for
  // the first value and then decides what to do. If it continues processing the RPC it uses this
  // wrapper type to turn the iterator back into an async sequence and then drops the iterator on
  // the floor so that there is only a single consumer of the original source.

  @usableFromInline
  typealias Element = Base.Element

  /// The base iterator.
  @usableFromInline
  private(set) var base: Base

  /// Set to `true` when an iterator has been made.
  @usableFromInline
  let _hasMadeIterator = Atomic(false)

  @inlinable
  init(_ base: Base) {
    self.base = base
  }

  @usableFromInline
  struct AsyncIterator: AsyncIteratorProtocol {
    @usableFromInline
    private(set) var base: Base

    @inlinable
    init(base: Base) {
      self.base = base
    }

    @inlinable
    mutating func next() async throws -> Element? {
      try await self.base.next()
    }
  }

  @inlinable
  func makeAsyncIterator() -> AsyncIterator {
    let (exchanged, original) = self._hasMadeIterator.compareExchange(
      expected: false,
      desired: true,
      ordering: .relaxed
    )

    guard exchanged else {
      fatalError("Only one iterator can be made")
    }

    assert(!original)
    return AsyncIterator(base: self.base)
  }
}
