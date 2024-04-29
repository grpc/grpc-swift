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

/// A type representing different possible server transport-related events.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct ServerTransportEvent: Sendable {
  public typealias AcceptedStreams = RPCAsyncSequence<
    RPCStream<ServerTransport.Inbound, ServerTransport.Outbound>
  >

  private enum Event: Sendable {
    case startedListening(acceptedStreams: AcceptedStreams)
    case failedToStartListening(any Error)
  }

  private let _event: Event

  private init(_event: Event) {
    self._event = _event
  }

  /// The call to ``ServerTransport/listen()`` was successful and the transport was started successfully.
  /// - Parameter acceptedStreams: The sequence of accepted streams for this transport.
  /// - Returns: An instance of ``ServerTransportEvent``.
  public static func startedListening(acceptedStreams: AcceptedStreams) -> Self {
    Self.init(_event: .startedListening(acceptedStreams: acceptedStreams))
  }

  /// The call to ``ServerTransport/listen()`` was unsuccesful and the transport failed to start.
  /// - Parameter error: The error with which the transport failed to start.
  /// - Returns: An instance of ``ServerTransportEvent``.
  public static func failedToStartListening(_ error: any Error) -> Self {
    Self.init(_event: .failedToStartListening(error))
  }

  /// If the ``ServerTransportEvent`` relates to the result of calling ``ServerTransport/listen()``,
  /// this property will return either the ``AcceptedStreams`` if successful, or an error if it failed.
  /// If the event does not relate to the transport's listening result, `nil` will be returned.
  public var listenResult: Result<AcceptedStreams, any Error>? {
    switch self._event {
    case .startedListening(let acceptedStreams):
      return .success(acceptedStreams)
    case .failedToStartListening(let error):
      return .failure(error)
    }
  }
}

/// A protocol server transport implementations must conform to.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol ServerTransport: Sendable {
  typealias Inbound = RPCAsyncSequence<RPCRequestPart>
  typealias Outbound = RPCWriter<RPCResponsePart>.Closable

  /// A sequence of ``TransportEvent``s, describing whether the transport was started successfully or not.
  ///
  /// This sequence should only return a single event. If multiple events are yielded into it, they may be ignored.
  /// Not yielding any events or finishing the sequence without yielding any events is considered a broken
  /// implementation of this protocol.
  ///
  /// Once ``listen()`` stops running, the sequence should be finished if it hasn't been finished already.
  var events: NoThrowRPCAsyncSequence<ServerTransportEvent> { get }

  /// Starts the transport.
  ///
  /// Implementations will typically bind to a listening port when this function is called
  /// and start accepting new connections. Each accepted inbound RPC stream should be published
  /// to the async sequence returned by the ``events`` property, in the successful
  /// ``ServerTransportEvent/startedListening(acceptedStreams:)`` case.
  ///
  /// If an implementation fails to start the transport, this error should be used to yield a
  /// ``ServerTransportEvent/failedToStartListening(_:)`` into the ``events``.
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
