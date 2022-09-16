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

/// This is currently a wrapper around AsyncThrowingStream because we want to be
/// able to swap out the implementation for something else in the future.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncRequestStream<Element: Sendable>: AsyncSequence {
  @usableFromInline
  enum Backing: Sendable {
    case passthroughMessageSequence(PassthroughMessageSequence<Element, Error>)
    case asyncStream(AsyncThrowingStream<Element, Error>)
  }

  @usableFromInline
  internal let backing: Backing

  @inlinable
  internal init(_ sequence: PassthroughMessageSequence<Element, Error>) {
    self.backing = .passthroughMessageSequence(sequence)
  }

  @inlinable
  public init(_ stream: AsyncThrowingStream<Element, Error>) {
    self.backing = .asyncStream(stream)
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    switch self.backing {
    case let .passthroughMessageSequence(sequence):
      return Self.AsyncIterator(.passthroughMessageSequence(sequence.makeAsyncIterator()))
    case let .asyncStream(stream):
      return Self.AsyncIterator(.asyncStream(stream.makeAsyncIterator()))
    }
  }

  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    enum BackingIterator {
      case passthroughMessageSequence(PassthroughMessageSequence<Element, Error>.Iterator)
      case asyncStream(AsyncThrowingStream<Element, Error>.Iterator)
    }

    @usableFromInline
    internal var iterator: BackingIterator

    @usableFromInline
    internal init(_ iterator: BackingIterator) {
      self.iterator = iterator
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      switch self.iterator {
      case let .passthroughMessageSequence(iterator):
        return try await iterator.next()
      case var .asyncStream(iterator):
        let element = try await iterator.next()
        self.iterator = .asyncStream(iterator)
        return element
      }
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncRequestStream: Sendable where Element: Sendable {}

#endif
