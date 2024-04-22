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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ServerTransport: Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  /// A sequence of accepted streams to handle.
  ///
  /// This property is `async` because implementations will typically require ``listen()`` to be called
  /// (and for the startup to be succesful) before a stream sequence can be returned.
  ///
  /// If the call to ``listen()`` throws, meaning the transport failed to start, implementations of this transport
  /// will typically throw upon getting this property.
  ///
  /// Once ``listen()`` stops running, the sequence will be finished.
  var acceptedStreams: RPCAsyncSequence<RPCStream<Inbound, Outbound>> { get async throws }

  /// Starts the transport and returns a sequence of accepted streams to handle.
  ///
  /// Implementations will typically bind to a listening port when this function is called
  /// and start accepting new connections. Each accepted inbound RPC stream should be published
  /// to the async sequence returned by the function.
  ///
  /// If an implementation throws when the transport fails to start, this error should be thrown when getting
  /// the ``acceptedStreams`` property.
  ///
  /// You can call ``stopListening()`` to stop the transport from accepting new streams. Existing
  /// streams must be allowed to complete naturally. However, transports may also enforce a grace
  /// period after which any open streams may be cancelled. You can also cancel the task running
  /// ``listen()`` to abruptly close connections and streams.
  func listen() async

  /// Indicates to the transport that no new streams should be accepted.
  ///
  /// Existing streams are permitted to run to completion. However, the transport may also enforce
  /// a grace period, after which remaining streams are cancelled.
  func stopListening()
}
