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
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncResponseStreamWriter<Response: Sendable> {
  @usableFromInline
  internal typealias Element = (Response, Compression)

  @usableFromInline
  internal typealias Delegate = AsyncResponseStreamWriterDelegate<Response>

  @usableFromInline
  internal let asyncWriter: AsyncWriter<Delegate>

  @inlinable
  internal init(wrapping asyncWriter: AsyncWriter<Delegate>) {
    self.asyncWriter = asyncWriter
  }

  @inlinable
  public func send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) async throws {
    try await self.asyncWriter.write((response, compression))
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
  internal let _context: GRPCAsyncServerCallContext

  @usableFromInline
  internal let _send: @Sendable (Response, MessageMetadata) -> Void

  @usableFromInline
  internal let _finish: @Sendable (GRPCStatus) -> Void

  @usableFromInline
  internal let _compressionEnabledOnServer: Bool

  // Create a new AsyncResponseStreamWriterDelegate.
  //
  // - Important: the `send` and `finish` closures must be thread-safe.
  @inlinable
  internal init(
    context: GRPCAsyncServerCallContext,
    compressionIsEnabled: Bool,
    send: @escaping @Sendable (Response, MessageMetadata) -> Void,
    finish: @escaping @Sendable (GRPCStatus) -> Void
  ) {
    self._context = context
    self._compressionEnabledOnServer = compressionIsEnabled
    self._send = send
    self._finish = finish
  }

  @inlinable
  internal func _shouldCompress(_ compression: Compression) -> Bool {
    guard self._compressionEnabledOnServer else {
      return false
    }
    return compression.isEnabled(callDefault: self._context.compressionEnabled)
  }

  @inlinable
  internal func _send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) {
    let compress = self._shouldCompress(compression)
    self._send(response, .init(compress: compress, flush: true))
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
