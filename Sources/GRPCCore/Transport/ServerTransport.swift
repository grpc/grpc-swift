/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

/// A protocol server transport implementations must conform to.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ServerTransport: Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  /// Starts the transport.
  ///
  /// Implementations will typically bind to a listening port when this function is called
  /// and start accepting new connections. Each accepted inbound RPC stream will be handed over to
  /// the provided `streamHandler` to handle accordingly.
  ///
  /// You can call ``stopListening()`` to stop the transport from accepting new streams. Existing
  /// streams must be allowed to complete naturally. However, transports may also enforce a grace
  /// period after which any open streams may be cancelled. You can also cancel the task running
  /// ``listen()`` to abruptly close connections and streams.
  func listen(
    _ streamHandler: @escaping (RPCStream<Inbound, Outbound>) async -> Void
  ) async throws

  /// Indicates to the transport that no new streams should be accepted.
  ///
  /// Existing streams are permitted to run to completion. However, the transport may also enforce
  /// a grace period, after which remaining streams are cancelled.
  func stopListening()
}
