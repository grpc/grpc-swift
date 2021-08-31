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
///
/// NOTE: This will be replaced by a pausible writer that is currently being worked on in parallel.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct GRPCAsyncResponseStreamWriter<Response> {
  @usableFromInline
  internal let _context: GRPCAsyncServerCallContext

  @usableFromInline
  internal let _send: (Response, MessageMetadata) async throws -> Void

  @usableFromInline
  internal let _compressionEnabledOnServer: Bool

  // Create a new AsyncResponseStreamWriter.
  //
  // - Important: the `send` closure must be thread-safe.
  @inlinable
  internal init(
    context: GRPCAsyncServerCallContext,
    compressionIsEnabled: Bool,
    send: @escaping (Response, MessageMetadata) async throws -> Void
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
  public func send(
    _ response: Response,
    compression: Compression = .deferToCallDefault
  ) async throws {
    let compress = self.shouldCompress(compression)
    try await self._send(response, .init(compress: compress, flush: true))
  }
}

#endif
