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
import NIOCore

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
  typealias AsyncWriter = NIOAsyncWriter<
    (Request, Compression),
    GRPCAsyncWriterSinkDelegate<(Request, Compression)>
  >

  @usableFromInline
  /* private */ internal let asyncWriter: AsyncWriter

  @inlinable
  internal init(asyncWriter: AsyncWriter) {
    self.asyncWriter = asyncWriter
  }

  /// Send a single request.
  ///
  /// It is safe to send multiple requests concurrently by sharing the ``GRPCAsyncRequestStreamWriter`` across tasks.
  ///
  /// Callers must call ``finish()`` when they have no more requests left to send.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - compression: Whether the request should be compressed or not. Ignored if compression was
  ///       not enabled for the RPC.
  /// - Throws: If the request stream has already been finished.
  @inlinable
  public func send(
    _ request: Request,
    compression: Compression = .deferToCallDefault
  ) async throws {
    try await self.asyncWriter.yield((request, compression))
  }

  /// Send a sequence of requests.
  ///
  /// It is safe to send multiple requests concurrently by sharing the ``GRPCAsyncRequestStreamWriter`` across tasks.
  ///
  /// Callers must call ``finish()`` when they have no more requests left to send.
  ///
  /// - Parameters:
  ///   - requests: The requests to send.
  ///   - compression: Whether the requests should be compressed or not. Ignored if compression was
  ///       not enabled for the RPC.
  /// - Throws: If the request stream has already been finished.
  @inlinable
  public func send<S: Sequence>(
    _ requests: S,
    compression: Compression = .deferToCallDefault
  ) async throws where S.Element == Request {
    try await self.asyncWriter.yield(contentsOf: requests.lazy.map { ($0, compression) })
  }

  /// Finish the request stream for the RPC. This must be called when there are no more requests to be sent.
  public func finish() {
    self.asyncWriter.finish()
  }

  /// Finish the request stream for the RPC with the given error.
  internal func finish(_ error: Error) {
    self.asyncWriter.finish(error: error)
  }
}

#endif // compiler(>=5.6)
