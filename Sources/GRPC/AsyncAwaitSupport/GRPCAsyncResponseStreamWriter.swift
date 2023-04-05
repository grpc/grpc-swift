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

/// Writer for server-streaming RPC handlers to provide responses.
///
/// To enable testability this type provides a static ``GRPCAsyncResponseStreamWriter/makeTestingResponseStreamWriter()``
/// method which allows you to create a stream that you can drive.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncResponseStreamWriter<Response: Sendable>: Sendable {
  @usableFromInline
  internal typealias AsyncWriter = NIOAsyncWriter<
    (Response, Compression),
    GRPCAsyncWriterSinkDelegate<(Response, Compression)>
  >

  /// An `AsyncSequence` backing a ``GRPCAsyncResponseStreamWriter`` for testing purposes.
  ///
  /// - Important: This `AsyncSequence` is never finishing.
  public struct ResponseStream: AsyncSequence {
    public typealias Element = (Response, Compression)

    @usableFromInline
    internal let stream: AsyncStream<(Response, Compression)>

    @usableFromInline
    internal let continuation: AsyncStream<(Response, Compression)>.Continuation

    @inlinable
    init(
      stream: AsyncStream<(Response, Compression)>,
      continuation: AsyncStream<(Response, Compression)>.Continuation
    ) {
      self.stream = stream
      self.continuation = continuation
    }

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(iterator: self.stream.makeAsyncIterator())
    }

    /// Finishes the response stream.
    ///
    /// This is useful in tests to finish the stream after the async method finished and allows you to collect all written responses.
    public func finish() {
      self.continuation.finish()
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
      @usableFromInline
      internal var iterator: AsyncStream<(Response, Compression)>.AsyncIterator

      @inlinable
      init(iterator: AsyncStream<(Response, Compression)>.AsyncIterator) {
        self.iterator = iterator
      }

      public mutating func next() async -> Element? {
        await self.iterator.next()
      }
    }
  }

  /// Simple struct for the return type of ``GRPCAsyncResponseStreamWriter/makeTestingResponseStreamWriter()``.
  ///
  /// This struct contains two properties:
  /// 1. The ``writer`` which is the actual ``GRPCAsyncResponseStreamWriter`` and should be passed to the method under testing.
  /// 2. The ``stream`` which can be used to observe the written responses.
  public struct TestingStreamWriter {
    /// The actual writer.
    public let writer: GRPCAsyncResponseStreamWriter<Response>
    /// The written responses in a stream.
    ///
    /// - Important: This `AsyncSequence` is never finishing.
    public let stream: ResponseStream

    @inlinable
    init(writer: GRPCAsyncResponseStreamWriter<Response>, stream: ResponseStream) {
      self.writer = writer
      self.stream = stream
    }
  }

  @usableFromInline
  enum Backing: Sendable {
    case asyncWriter(AsyncWriter)
    case closure(@Sendable ((Response, Compression)) async -> Void)
  }

  @usableFromInline
  internal let backing: Backing

  @inlinable
  internal init(wrapping asyncWriter: AsyncWriter) {
    self.backing = .asyncWriter(asyncWriter)
  }

  @inlinable
  internal init(onWrite: @escaping @Sendable ((Response, Compression)) async -> Void) {
    self.backing = .closure(onWrite)
  }

  @inlinable
  public func send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) async throws {
    switch self.backing {
    case let .asyncWriter(writer):
      try await writer.yield((response, compression))

    case let .closure(closure):
      await closure((response, compression))
    }
  }

  @inlinable
  public func send<S: Sequence>(
    contentsOf responses: S,
    compression: Compression = .deferToCallDefault
  ) async throws where S.Element == Response {
    let responsesWithCompression = responses.lazy.map { ($0, compression) }
    switch self.backing {
    case let .asyncWriter(writer):
      try await writer.yield(contentsOf: responsesWithCompression)

    case let .closure(closure):
      for response in responsesWithCompression {
        await closure(response)
      }
    }
  }

  /// Creates a new `GRPCAsyncResponseStreamWriter` backed by a ``ResponseStream``.
  /// This is mostly useful for testing purposes where one wants to observe the written responses.
  ///
  /// - Note: For most tests it is useful to call ``ResponseStream/finish()`` after the async method under testing
  /// resumed. This allows you to easily collect all written responses.
  @inlinable
  public static func makeTestingResponseStreamWriter() -> TestingStreamWriter {
    var continuation: AsyncStream<(Response, Compression)>.Continuation!
    let asyncStream = AsyncStream<(Response, Compression)> { cont in
      continuation = cont
    }
    let writer = Self.init { [continuation] in
      continuation!.yield($0)
    }
    let responseStream = ResponseStream(
      stream: asyncStream,
      continuation: continuation
    )

    return TestingStreamWriter(writer: writer, stream: responseStream)
  }
}
