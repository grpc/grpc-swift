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

/// Writer for server-streaming RPC handlers to provide responses.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct GRPCAsyncResponseStreamWriter<Response> {
  @usableFromInline
  internal typealias Delegate = AsyncResponseStreamWriterDelegate<Response>

  @usableFromInline
  internal let _asyncWriter: AsyncWriter<Delegate>

  @inlinable
  internal init(wrapping asyncWriter: AsyncWriter<Delegate>) {
    self._asyncWriter = asyncWriter
  }

  @inlinable
  public func send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) async throws {
    try await self._asyncWriter.write((response, compression))
  }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
@usableFromInline
internal final class AsyncResponseStreamWriterDelegate<Response>: AsyncWriterDelegate {
  @usableFromInline
  internal let _context: GRPCAsyncServerCallContext

  @usableFromInline
  internal let _send: (Response, MessageMetadata) -> Void

  @usableFromInline
  internal let _compressionEnabledOnServer: Bool

  // Create a new AsyncResponseStreamWriterDelegate.
  //
  // - Important: the `send` closure must be thread-safe.
  @inlinable
  internal init(
    context: GRPCAsyncServerCallContext,
    compressionIsEnabled: Bool,
    send: @escaping (Response, MessageMetadata) -> Void
  ) {
    self._context = context
    self._compressionEnabledOnServer = compressionIsEnabled
    self._send = send
  }

  @inlinable
  internal func shouldCompress(_ compression: Compression) -> Bool {
    guard self._compressionEnabledOnServer else {
      return false
    }
    return compression.isEnabled(callDefault: self._context.compressionEnabled)
  }

  @inlinable
  internal func send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) {
    let compress = self.shouldCompress(compression)
    self._send(response, .init(compress: compress, flush: true))
  }

  // MARK: - AsyncWriterDelegate conformance.

  @inlinable
  internal func write(_ response: (Response, Compression)) {
    self.send(response.0, compression: response.1)
  }

  @inlinable
  internal func writeEnd(_ end: Void) {
    // meh.
    // TODO: is this where will move the state on to completed somehow?
  }
}

#endif
