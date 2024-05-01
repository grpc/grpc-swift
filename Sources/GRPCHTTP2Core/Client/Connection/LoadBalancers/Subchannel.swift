/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import GRPCCore
import NIOConcurrencyHelpers

/// A ``Subchannel`` provides communication to a single ``Endpoint``.
///
/// Each ``Subchannel`` starts in an 'idle' state where it isn't attempting to connect to an
/// endpoint. You can tell it to start connecting by calling ``connect()`` and you can listen
/// to connectivity state changes by consuming the ``events`` sequence.
///
/// You must call ``close()`` on the ``Subchannel`` when it's no longer required. This will move
/// it to the ``ConnectivityState/shutdown`` state: existing RPCs may continue but all subsequent
/// calls to ``makeStream(descriptor:options:)`` will fail.
///
/// To use the ``Subchannel`` you must run it in a task:
///
/// ```swift
/// await withTaskGroup(of: Void.self) { group in
///   group.addTask { await subchannel.run() }
///
///   for await event in subchannel.events {
///     switch event {
///     case .connectivityStateChanged(.ready):
///       // ...
///     default:
///       // ...
///     }
///   }
/// }
/// ```
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct Subchannel {
  enum Event: Sendable, Hashable {
    /// The connection received a GOAWAY and will close soon. No new streams
    /// should be opened on this connection.
    case goingAway
    /// The connectivity state of the subchannel changed.
    case connectivityStateChanged(ConnectivityState)
    /// The subchannel requests that the load balancer re-resolves names.
    case requiresNameResolution
  }

  private enum Input: Sendable {
    /// Request that the connection starts connecting.
    case connect
    /// A backoff period has ended.
    case backedOff
    /// Close the connection, if possible.
    case close
    /// Handle the event from the underlying connection object.
    case handleConnectionEvent(Connection.Event)
  }

  /// Events which can happen to the subchannel.
  private let event: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation)

  /// Inputs which this subchannel should react to.
  private let input: (stream: AsyncStream<Input>, continuation: AsyncStream<Input>.Continuation)

  /// The state of the subchannel.
  private let state: NIOLockedValueBox<State>

  /// The endpoint this subchannel is targeting.
  let endpoint: Endpoint

  /// The ID of the subchannel.
  let id: SubchannelID

  /// A factory for connections.
  private let connector: any HTTP2Connector

  /// The connection backoff configuration used by the subchannel when establishing a connection.
  private let backoff: ConnectionBackoff

  /// The default compression algorithm used for requests.
  private let defaultCompression: CompressionAlgorithm

  /// The set of enabled compression algorithms.
  private let enabledCompression: CompressionAlgorithmSet

  init(
    endpoint: Endpoint,
    id: SubchannelID,
    connector: any HTTP2Connector,
    backoff: ConnectionBackoff,
    defaultCompression: CompressionAlgorithm,
    enabledCompression: CompressionAlgorithmSet
  ) {
    assert(!endpoint.addresses.isEmpty, "endpoint.addresses mustn't be empty")

    self.state = NIOLockedValueBox(.notConnected)
    self.endpoint = endpoint
    self.id = id
    self.connector = connector
    self.backoff = backoff
    self.defaultCompression = defaultCompression
    self.enabledCompression = enabledCompression
    self.event = AsyncStream.makeStream(of: Event.self)
    self.input = AsyncStream.makeStream(of: Input.self)
    // Subchannel always starts in the idle state.
    self.event.continuation.yield(.connectivityStateChanged(.idle))
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension Subchannel {
  /// A stream of events which can happen to the subchannel.
  var events: AsyncStream<Event> {
    self.event.stream
  }

  /// Run the subchannel.
  ///
  /// Running the subchannel will attempt to maintain a connection to a remote endpoint. At times
  /// the connection may be idle but it will reconnect on-demand when a stream is requested. If
  /// connect attempts fail then the subchannel may progressively spend longer in a transient
  /// failure state.
  ///
  /// Events and state changes can be observed via the ``events`` stream.
  func run() async {
    await withDiscardingTaskGroup { group in
      for await input in self.input.stream {
        switch input {
        case .connect:
          self.handleConnectInput(in: &group)
        case .backedOff:
          self.handleBackedOffInput(in: &group)
        case .close:
          self.handleCloseInput(in: &group)
        case .handleConnectionEvent(let event):
          self.handleConnectionEvent(event, in: &group)
        }
      }
    }

    // Once the task group is done, the event stream must also be finished. In normal operation
    // this is handled via other paths. For cancellation it must be finished explicitly.
    if Task.isCancelled {
      self.event.continuation.finish()
    }
  }

  /// Initiate a connection attempt, if possible.
  func connect() {
    self.input.continuation.yield(.connect)
  }

  /// Initiates graceful shutdown, if possible.
  func close() {
    self.input.continuation.yield(.close)
  }

  /// Make a stream using the subchannel if it's ready.
  ///
  /// - Parameter descriptor: A descriptor of the method to create a stream for.
  /// - Returns: The open stream.
  func makeStream(
    descriptor: MethodDescriptor,
    options: CallOptions
  ) async throws -> Connection.Stream {
    let connection: Connection? = self.state.withLockedValue { state in
      switch state {
      case .notConnected, .connecting, .closing, .closed:
        return nil
      case .connected(let connected):
        return connected.connection
      }
    }

    guard let connection = connection else {
      throw RPCError(code: .unavailable, message: "subchannel isn't ready")
    }

    return try await connection.makeStream(descriptor: descriptor, options: options)
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension Subchannel {
  private func handleConnectInput(in group: inout DiscardingTaskGroup) {
    let connection = self.state.withLockedValue { state in
      state.makeConnection(
        to: self.endpoint.addresses,
        using: self.connector,
        backoff: self.backoff,
        defaultCompression: self.defaultCompression,
        enabledCompression: self.enabledCompression
      )
    }

    guard let connection = connection else {
      // Not in a state to start a connection.
      return
    }

    // About to start connecting a new connection; emit a state change event.
    self.event.continuation.yield(.connectivityStateChanged(.connecting))
    self.runConnection(connection, in: &group)
  }

  private func handleBackedOffInput(in group: inout DiscardingTaskGroup) {
    switch self.state.withLockedValue({ $0.backedOff() }) {
    case .none:
      ()

    case .connect(let connection):
      // About to start connecting, emit a state change event.
      self.event.continuation.yield(.connectivityStateChanged(.connecting))
      self.runConnection(connection, in: &group)

    case .shutdown:
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      // Close the event streams.
      self.event.continuation.finish()
      self.input.continuation.finish()
    }
  }

  private func handleCloseInput(in group: inout DiscardingTaskGroup) {
    switch self.state.withLockedValue({ $0.close() }) {
    case .none:
      ()

    case .close(let connection):
      connection.close()

    case .shutdown:
      // Connection closed because the load balancer asked it to, so notify the load balancer.
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      // At this point there are no more events: close the event streams.
      self.event.continuation.finish()
      self.input.continuation.finish()
    }
  }

  private func handleConnectionEvent(
    _ event: Connection.Event,
    in group: inout DiscardingTaskGroup
  ) {
    switch event {
    case .connectSucceeded:
      self.handleConnectSucceededEvent()
    case .connectFailed:
      self.handleConnectFailedEvent(in: &group)
    case .goingAway:
      self.handleGoingAwayEvent()
    case .closed(let reason):
      self.handleConnectionClosedEvent(reason, in: &group)
    }
  }

  private func handleConnectSucceededEvent() {
    switch self.state.withLockedValue({ $0.connectSucceeded() }) {
    case .updateState:
      // Emit a connectivity state change: the load balancer can now use this subchannel.
      self.event.continuation.yield(.connectivityStateChanged(.ready))

    case .close(let connection):
      connection.close()

    case .none:
      ()
    }
  }

  private func handleConnectFailedEvent(in group: inout DiscardingTaskGroup) {
    let onConnectFailed = self.state.withLockedValue { $0.connectFailed(connector: self.connector) }
    switch onConnectFailed {
    case .connect(let connection):
      // Try the next address.
      self.runConnection(connection, in: &group)

    case .backoff(let duration):
      // All addresses have been tried, backoff for some time.
      self.event.continuation.yield(.connectivityStateChanged(.transientFailure))
      group.addTask {
        do {
          try await Task.sleep(for: duration)
          self.input.continuation.yield(.backedOff)
        } catch {
          // Can only be a cancellation error, swallow it. No further connection attempts will be
          // made.
          ()
        }
      }

    case .shutdown:
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))
      // No more events, close the streams.
      self.event.continuation.finish()
      self.input.continuation.finish()

    case .none:
      ()
    }
  }

  private func handleGoingAwayEvent() {
    let isGoingAway = self.state.withLockedValue { $0.goingAway() }
    guard isGoingAway else { return }

    // Notify the load balancer that the subchannel is going away to stop it from being used.
    self.event.continuation.yield(.goingAway)
    // A GOAWAY also means that the load balancer should re-resolve as the available servers
    // may have changed.
    self.event.continuation.yield(.requiresNameResolution)
  }

  private func handleConnectionClosedEvent(
    _ reason: Connection.CloseReason,
    in group: inout DiscardingTaskGroup
  ) {
    let isClosed = self.state.withLockedValue { $0.closed(reason: reason) }
    guard isClosed else { return }

    switch reason {
    case .idleTimeout:
      // Connection closed due to an idle timeout; notify the load balancer about this.
      self.event.continuation.yield(.connectivityStateChanged(.idle))

    case .keepaliveTimeout, .error:
      // Unclean closes trigger a transient failure state change and a name resolution.
      self.event.continuation.yield(.connectivityStateChanged(.transientFailure))
      self.event.continuation.yield(.requiresNameResolution)

      // Attempt to reconnect.
      self.handleConnectInput(in: &group)

    case .initiatedLocally, .remote:
      // Connection closed because the load balancer (or remote peer) asked it to, so notify the
      // load balancer. In the case of 'remote' (i.e. a GOAWAY), the load balancer will have
      // already reacted to a separate 'goingAway' event.
      self.event.continuation.yield(.connectivityStateChanged(.shutdown))

      // At this point there are no more events: close the event streams.
      self.event.continuation.finish()
      self.input.continuation.finish()
    }
  }

  private func runConnection(_ connection: Connection, in group: inout DiscardingTaskGroup) {
    group.addTask {
      await connection.run()
    }

    group.addTask {
      for await event in connection.events {
        self.input.continuation.yield(.handleConnectionEvent(event))
      }
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension Subchannel {
  private enum State {
    /// Not connected and not actively connecting.
    case notConnected
    /// A connection attempt is in-progress.
    case connecting(Connecting)
    /// A connection has been established.
    case connected(Connected)
    /// The subchannel is closing.
    case closing(Closing)
    /// The subchannel is closed.
    case closed

    struct Connecting {
      var connection: Connection
      let addresses: [SocketAddress]
      var addressIterator: Array<SocketAddress>.Iterator
      var backoff: ConnectionBackoff.Iterator
    }

    struct Connected {
      var connection: Connection

      init(from state: Connecting) {
        self.connection = state.connection
      }
    }

    struct Closing {
      var connection: Connection

      init(from state: Connecting) {
        self.connection = state.connection
      }

      init(from state: Connected) {
        self.connection = state.connection
      }
    }

    mutating func makeConnection(
      to addresses: [SocketAddress],
      using connector: any HTTP2Connector,
      backoff: ConnectionBackoff,
      defaultCompression: CompressionAlgorithm,
      enabledCompression: CompressionAlgorithmSet
    ) -> Connection? {
      switch self {
      case .notConnected:
        var iterator = addresses.makeIterator()
        let address = iterator.next()!  // addresses must not be empty.

        let connection = Connection(
          address: address,
          http2Connector: connector,
          defaultCompression: defaultCompression,
          enabledCompression: enabledCompression
        )

        let connecting = State.Connecting(
          connection: connection,
          addresses: addresses,
          addressIterator: iterator,
          backoff: backoff.makeIterator()
        )

        self = .connecting(connecting)
        return connection

      case .connecting, .connected, .closing, .closed:
        return nil
      }
    }

    enum OnClose {
      case none
      case shutdown
      case close(Connection)
    }

    mutating func close() -> OnClose {
      let onClose: OnClose

      switch self {
      case .notConnected:
        onClose = .shutdown

      case .connecting(let state):
        self = .closing(Closing(from: state))
        // Do nothing; the connection hasn't been established yet so can't be closed.
        onClose = .none

      case .connected(let state):
        self = .closing(Closing(from: state))
        onClose = .close(state.connection)

      case .closing, .closed:
        onClose = .none
      }

      return onClose
    }

    enum OnConnectSucceeded {
      case updateState
      case close(Connection)
      case none
    }

    mutating func connectSucceeded() -> OnConnectSucceeded {
      switch self {
      case .connecting(let state):
        self = .connected(Connected(from: state))
        return .updateState
      case .closing(let state):
        self = .closing(state)
        return .close(state.connection)
      case .notConnected, .connected, .closed:
        return .none
      }
    }

    enum OnConnectFailed {
      case none
      case connect(Connection)
      case backoff(Duration)
      case shutdown
    }

    mutating func connectFailed(connector: any HTTP2Connector) -> OnConnectFailed {
      switch self {
      case .connecting(var connecting):
        if let address = connecting.addressIterator.next() {
          connecting.connection = Connection(
            address: address,
            http2Connector: connector,
            defaultCompression: .none,
            enabledCompression: .all
          )
          self = .connecting(connecting)
          return .connect(connecting.connection)
        } else {
          connecting.addressIterator = connecting.addresses.makeIterator()
          let address = connecting.addressIterator.next()!
          connecting.connection = Connection(
            address: address,
            http2Connector: connector,
            defaultCompression: .none,
            enabledCompression: .all
          )
          let backoff = connecting.backoff.next()
          self = .connecting(connecting)
          return .backoff(backoff)
        }

      case .closing:
        self = .closed
        return .shutdown

      case .notConnected, .connected, .closed:
        return .none
      }
    }

    enum OnBackedOff {
      case none
      case connect(Connection)
      case shutdown
    }

    mutating func backedOff() -> OnBackedOff {
      switch self {
      case .connecting(let state):
        return .connect(state.connection)
      case .closing:
        self = .closed
        return .shutdown
      case .notConnected, .connected, .closed:
        return .none
      }
    }

    mutating func goingAway() -> Bool {
      switch self {
      case .connected(let state):
        self = .closing(Closing(from: state))
        return true
      case .notConnected, .closing, .connecting, .closed:
        return false
      }
    }

    mutating func closed(reason: Connection.CloseReason) -> Bool {
      switch self {
      case .connected, .closing:
        switch reason {
        case .idleTimeout, .keepaliveTimeout, .error:
          self = .notConnected
        case .initiatedLocally, .remote:
          self = .closed
        }

        return true
      case .notConnected, .connecting, .closed:
        return false
      }
    }
  }
}
