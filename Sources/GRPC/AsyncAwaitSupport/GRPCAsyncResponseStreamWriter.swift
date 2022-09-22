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

/// Writer for server-streaming RPC handlers to provide responses.
///
/// To enable testability this type provides a static ``GRPCAsyncResponseStreamWriter/makeResponseStreamWriter()``
/// method which allows you to create a stream that you can drive.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncResponseStreamWriter<Response: Sendable>: Sendable {
  /// An `AsyncSequence` backing a ``GRPCAsyncResponseStreamWriter`` for testing purposes.
  ///
  /// - Important: This `AsyncSequence` is never finishing.
  public struct ResponseStream: AsyncSequence {
    public typealias Element = (Response, Compression)

    @usableFromInline
    internal let stream: AsyncStream<(Response, Compression)>

    @inlinable
    init(stream: AsyncStream<(Response, Compression)>) {
      self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(iterator: self.stream.makeAsyncIterator())
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

  /// Simple struct for the return type of ``GRPCAsyncResponseStreamWriter/makeResponseStreamWriter()``.
  ///
  /// This struct contains two properties:
  /// 1. The ``writer`` which is the actual ``GRPCAsyncResponseStreamWriter`` and should be passed to the method under testing.
  /// 2. The ``stream`` which can be used to observe the written responses.
  public struct ResponseStreamWriter {
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
    case asyncWriter(AsyncWriter<Delegate>)
    case closure(@Sendable ((Response, Compression)) async -> Void)
  }

  @usableFromInline
  internal typealias Element = (Response, Compression)

  @usableFromInline
  internal typealias Delegate = AsyncResponseStreamWriterDelegate<Response>

  @usableFromInline
  internal let backing: Backing

  @inlinable
  internal init(wrapping asyncWriter: AsyncWriter<Delegate>) {
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
      try await writer.write((response, compression))

    case let .closure(closure):
      await closure((response, compression))
    }
  }

  /// Creates a new `GRPCAsyncResponseStreamWriter` backed by a ``ResponseStream``.
  /// This is mostly useful for testing purposes where one wants to observe the written responses.
  @inlinable
  public static func makeResponseStreamWriter() -> ResponseStreamWriter {
    var continuation: AsyncStream<(Response, Compression)>.Continuation!
    let asyncStream = AsyncStream<(Response, Compression)> { cont in
      continuation = cont
    }
    let writer = Self.init { [continuation] in
      continuation!.yield($0)
    }

    return ResponseStreamWriter(writer: writer, stream: ResponseStream(stream: asyncStream))
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal final class AsyncResponseStreamWriterDelegate<Response: Sendable>: AsyncWriterDelegate {
  @usableFromInline
  internal typealias Element = (Response, Compression)

  @usableFromInline
  internal typealias End = GRPCStatus

  @usableFromInline
  internal let _send: @Sendable (Response, Compression) -> Void

  @usableFromInline
  internal let _finish: @Sendable (GRPCStatus) -> Void

  // Create a new AsyncResponseStreamWriterDelegate.
  //
  // - Important: the `send` and `finish` closures must be thread-safe.
  @inlinable
  internal init(
    send: @escaping @Sendable (Response, Compression) -> Void,
    finish: @escaping @Sendable (GRPCStatus) -> Void
  ) {
    self._send = send
    self._finish = finish
  }

  @inlinable
  internal func _send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) {
    self._send(response, compression)
  }

  // MARK: - AsyncWriterDelegate conformance.

  @inlinable
  internal func write(_ element: (Response, Compression)) {
    self._send(element.0, compression: element.1)
  }

  @inlinable
  internal func writeEnd(_ end: GRPCStatus) {
    self._finish(end)
  }
}

#endif
