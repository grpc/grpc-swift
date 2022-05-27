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
public struct GRPCAsyncResponseStream<Element>: AsyncSequence {
  @usableFromInline
  internal typealias WrappedStream = PassthroughMessageSequence<Element, Error>

  @usableFromInline
  internal let stream: WrappedStream

  @inlinable
  internal init(_ stream: WrappedStream) {
    self.stream = stream
  }

  public func makeAsyncIterator() -> Iterator {
    Self.AsyncIterator(self.stream)
  }

  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    internal var iterator: WrappedStream.AsyncIterator

    fileprivate init(_ stream: WrappedStream) {
      self.iterator = stream.makeAsyncIterator()
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      if Task.isCancelled { throw GRPCStatus(code: .cancelled) }
      return try await self.iterator.next()
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncResponseStream: Sendable where Element: Sendable {}
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncResponseStream.Iterator: Sendable where Element: Sendable {}

#endif
