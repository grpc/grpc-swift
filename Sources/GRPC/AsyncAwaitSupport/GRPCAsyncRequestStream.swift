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
import NIOCore

/// A type for the stream of request messages send to a gRPC server method.
///
/// To enable testability this type provides a static ``GRPCAsyncRequestStream/makeTestingRequestStream()``
/// method which allows you to create a stream that you can drive.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncRequestStream<Element: Sendable>: AsyncSequence {
  @usableFromInline
  internal typealias _AsyncSequenceProducer = NIOThrowingAsyncSequenceProducer<
    Element,
    Error,
    NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark,
    GRPCAsyncSequenceProducerDelegate
  >

  /// A source used for driving a ``GRPCAsyncRequestStream`` during tests.
  public struct Source {
    @usableFromInline
    internal let continuation: AsyncThrowingStream<Element, Error>.Continuation

    @inlinable
    init(continuation: AsyncThrowingStream<Element, Error>.Continuation) {
      self.continuation = continuation
    }

    /// Yields the element to the request stream.
    ///
    /// - Parameter element: The element to yield to the request stream.
    @inlinable
    public func yield(_ element: Element) {
      self.continuation.yield(element)
    }

    /// Finished the request stream.
    @inlinable
    public func finish() {
      self.continuation.finish()
    }

    /// Finished the request stream.
    ///
    /// - Parameter error: An optional `Error` to finish the request stream with.
    @inlinable
    public func finish(throwing error: Error?) {
      self.continuation.finish(throwing: error)
    }
  }

  /// Simple struct for the return type of ``GRPCAsyncRequestStream/makeTestingRequestStream()``.
  ///
  /// This struct contains two properties:
  /// 1. The ``stream`` which is the actual ``GRPCAsyncRequestStream`` and should be passed to the method under testing.
  /// 2. The ``source`` which can be used to drive the stream.
  public struct TestingStream {
    /// The actual stream.
    public let stream: GRPCAsyncRequestStream<Element>
    /// The source used to drive the stream.
    public let source: Source

    @inlinable
    init(stream: GRPCAsyncRequestStream<Element>, source: Source) {
      self.stream = stream
      self.source = source
    }
  }

  @usableFromInline
  enum Backing: Sendable {
    case asyncStream(AsyncThrowingStream<Element, Error>)
    case throwingAsyncSequenceProducer(_AsyncSequenceProducer)
  }

  @usableFromInline
  internal let backing: Backing

  @inlinable
  internal init(_ sequence: _AsyncSequenceProducer) {
    self.backing = .throwingAsyncSequenceProducer(sequence)
  }

  @inlinable
  internal init(_ stream: AsyncThrowingStream<Element, Error>) {
    self.backing = .asyncStream(stream)
  }

  /// Creates a new testing stream.
  ///
  /// This is useful for writing unit tests for your gRPC method implementations since it allows you to drive the stream passed
  /// to your method.
  ///
  /// - Returns: A new ``TestingStream`` containing the actual ``GRPCAsyncRequestStream`` and a ``Source``.
  @inlinable
  public static func makeTestingRequestStream() -> TestingStream {
    var continuation: AsyncThrowingStream<Element, Error>.Continuation!
    let stream = AsyncThrowingStream<Element, Error> { continuation = $0 }
    let source = Source(continuation: continuation)
    let requestStream = Self(stream)
    return TestingStream(stream: requestStream, source: source)
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    switch self.backing {
    case let .asyncStream(stream):
      return Self.AsyncIterator(.asyncStream(stream.makeAsyncIterator()))
    case let .throwingAsyncSequenceProducer(sequence):
      return Self.AsyncIterator(.throwingAsyncSequenceProducer(sequence.makeAsyncIterator()))
    }
  }

  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    enum BackingIterator {
      case asyncStream(AsyncThrowingStream<Element, Error>.Iterator)
      case throwingAsyncSequenceProducer(_AsyncSequenceProducer.AsyncIterator)
    }

    @usableFromInline
    internal var iterator: BackingIterator

    @usableFromInline
    internal init(_ iterator: BackingIterator) {
      self.iterator = iterator
    }

    @inlinable
    public mutating func next() async throws -> Element? {
      if Task.isCancelled { throw GRPCStatus(code: .cancelled) }
      switch self.iterator {
      case var .asyncStream(iterator):
        let element = try await iterator.next()
        self.iterator = .asyncStream(iterator)
        return element
      case let .throwingAsyncSequenceProducer(iterator):
        return try await iterator.next()
      }
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncRequestStream: Sendable where Element: Sendable {}
