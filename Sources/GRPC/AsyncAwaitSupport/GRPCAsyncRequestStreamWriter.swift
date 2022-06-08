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

/// An object allowing the holder -- a client -- to send requests on an RPC.
///
/// Requests may be sent using ``send(_:compression:)``. After all requests have been sent
/// the user is responsible for closing the request stream by calling ``finish()``.
///
/// ```
/// // Send a request on the request stream, use the compression setting configured for the RPC.
/// try await stream.send(request)
///
/// // Send a request and explicitly disable compression.
/// try await stream.send(request, compression: .disabled)
///
/// // Finish the stream to indicate that no more messages will be sent.
/// try await stream.finish()
/// ```
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncRequestStreamWriter<Request: Sendable>: Sendable {
  @usableFromInline
  internal let asyncWriter: AsyncWriter<Delegate<Request>>

  @inlinable
  internal init(asyncWriter: AsyncWriter<Delegate<Request>>) {
    self.asyncWriter = asyncWriter
  }

  /// Send a single request.
  ///
  /// To ensure requests are delivered in order callers should `await` the result of this call
  /// before sending another request. Callers who do not need this guarantee do not have to `await`
  /// the completion of this call and may send messages concurrently from multiple ``Task``s.
  /// However, it is important to note that no more than 16 writes may be pending at any one time
  /// and attempting to exceed this will result in an ``GRPCAsyncWriterError.tooManyPendingWrites``
  /// error being thrown.
  ///
  /// Callers must call ``finish()`` when they have no more requests left to send.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - compression: Whether the request should be compressed or not. Ignored if compression was
  ///       not enabled for the RPC.
  /// - Throws: ``GRPCAsyncWriterError`` if there are too many pending writes or the request stream
  ///     has already been finished.
  @inlinable
  public func send(
    _ request: Request,
    compression: Compression = .deferToCallDefault
  ) async throws {
    try await self.asyncWriter.write((request, compression))
  }

  /// Finish the request stream for the RPC. This must be called when there are no more requests to
  /// be sent.
  ///
  /// - Throws: ``GRPCAsyncWriterError`` if the request stream has already been finished.
  public func finish() async throws {
    try await self.asyncWriter.finish()
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncRequestStreamWriter {
  /// A delegate for the writer which writes messages to an underlying receiver.`
  @usableFromInline
  internal final class Delegate<Request: Sendable>: AsyncWriterDelegate, Sendable {
    @usableFromInline
    internal typealias Element = (Request, Compression)

    @usableFromInline
    internal typealias End = Void

    @usableFromInline
    internal let _compressionEnabled: Bool

    @usableFromInline
    internal let _send: @Sendable (Request, MessageMetadata) -> Void

    @usableFromInline
    internal let _finish: @Sendable () -> Void

    @inlinable
    internal init(
      compressionEnabled: Bool,
      send: @Sendable @escaping (Request, MessageMetadata) -> Void,
      finish: @Sendable @escaping () -> Void
    ) {
      self._compressionEnabled = compressionEnabled
      self._send = send
      self._finish = finish
    }

    @inlinable
    internal func write(_ element: (Request, Compression)) {
      let (request, compression) = element
      let compress = compression.isEnabled(callDefault: self._compressionEnabled)

      // TODO: be smarter about inserting flushes.
      //
      // We currently always flush after every write which may trigger more syscalls than necessary.
      let metadata = MessageMetadata(compress: compress, flush: true)
      self._send(request, metadata)
    }

    @inlinable
    internal func writeEnd(_ end: Void) {
      self._finish()
    }
  }
}

#endif // compiler(>=5.6)
