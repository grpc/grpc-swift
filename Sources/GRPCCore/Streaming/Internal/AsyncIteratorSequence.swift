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
import Atomics

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@usableFromInline
/// An `AsyncSequence` which wraps an existing async iterator.
struct AsyncIteratorSequence<Base: AsyncIteratorProtocol>: AsyncSequence {
  @usableFromInline
  typealias Element = Base.Element

  /// The base iterator.
  @usableFromInline
  private(set) var base: Base

  /// Set to `true` when an iterator has been made.
  @usableFromInline
  let _hasMadeIterator = ManagedAtomic(false)

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
