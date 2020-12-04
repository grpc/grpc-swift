/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Foundation
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOHTTP2

internal class ConnectionManager {
  internal enum Reconnect {
    case none
    case after(TimeInterval)
  }

  internal struct ConnectingState {
    var backoffIterator: ConnectionBackoffIterator?
    var reconnect: Reconnect

    var candidate: EventLoopFuture<Channel>
    var readyChannelMuxPromise: EventLoopPromise<HTTP2StreamMultiplexer>
    var candidateMuxPromise: EventLoopPromise<HTTP2StreamMultiplexer>
  }

  internal struct ConnectedState {
    var backoffIterator: ConnectionBackoffIterator?
    var reconnect: Reconnect
    var candidate: Channel
    var readyChannelMuxPromise: EventLoopPromise<HTTP2StreamMultiplexer>
    var multiplexer: HTTP2StreamMultiplexer
    var error: Error?

    init(from state: ConnectingState, candidate: Channel, multiplexer: HTTP2StreamMultiplexer) {
      self.backoffIterator = state.backoffIterator
      self.reconnect = state.reconnect
      self.candidate = candidate
      self.readyChannelMuxPromise = state.readyChannelMuxPromise
      self.multiplexer = multiplexer
    }
  }

  internal struct ReadyState {
    var channel: Channel
    var multiplexer: HTTP2StreamMultiplexer
    var error: Error?

    init(from state: ConnectedState) {
      self.channel = state.candidate
      self.multiplexer = state.multiplexer
    }
  }

  internal struct TransientFailureState {
    var backoffIterator: ConnectionBackoffIterator?
    var readyChannelMuxPromise: EventLoopPromise<HTTP2StreamMultiplexer>
    var scheduled: Scheduled<Void>
    var reason: Error?

    init(from state: ConnectingState, scheduled: Scheduled<Void>, reason: Error) {
      self.backoffIterator = state.backoffIterator
      self.readyChannelMuxPromise = state.readyChannelMuxPromise
      self.scheduled = scheduled
      self.reason = reason
    }

    init(from state: ConnectedState, scheduled: Scheduled<Void>) {
      self.backoffIterator = state.backoffIterator
      self.readyChannelMuxPromise = state.readyChannelMuxPromise
      self.scheduled = scheduled
      self.reason = state.error
    }

    init(
      from state: ReadyState,
      scheduled: Scheduled<Void>,
      backoffIterator: ConnectionBackoffIterator?
    ) {
      self.backoffIterator = backoffIterator
      self.readyChannelMuxPromise = state.channel.eventLoop.makePromise()
      self.scheduled = scheduled
      self.reason = state.error
    }
  }

  internal struct ShutdownState {
    var closeFuture: EventLoopFuture<Void>
    /// The reason we are shutdown. Any requests for a `Channel` in this state will be failed with
    /// this error.
    var reason: Error

    init(closeFuture: EventLoopFuture<Void>, reason: Error) {
      self.closeFuture = closeFuture
      self.reason = reason
    }

    static func shutdownByUser(closeFuture: EventLoopFuture<Void>) -> ShutdownState {
      return ShutdownState(
        closeFuture: closeFuture,
        reason: GRPCStatus(code: .unavailable, message: "Connection was shutdown by the user")
      )
    }
  }

  internal enum State {
    /// No `Channel` is required.
    ///
    /// Valid next states:
    /// - `connecting`
    /// - `shutdown`
    case idle

    /// We're actively trying to establish a connection.
    ///
    /// Valid next states:
    /// - `active`
    /// - `transientFailure` (if our attempt fails and we're going to try again)
    /// - `shutdown`
    case connecting(ConnectingState)

    /// We've established a `Channel`, it might not be suitable (TLS handshake may fail, etc.).
    /// Our signal to be 'ready' is the initial HTTP/2 SETTINGS frame.
    ///
    /// Valid next states:
    /// - `ready`
    /// - `transientFailure` (if we our handshake fails or other error happens and we can attempt
    ///   to re-establish the connection)
    /// - `shutdown`
    case active(ConnectedState)

    /// We have an active `Channel` which has seen the initial HTTP/2 SETTINGS frame. We can use
    /// the channel for making RPCs.
    ///
    /// Valid next states:
    /// - `idle` (we're not serving any RPCs, we can drop the connection for now)
    /// - `transientFailure` (we encountered an error and will re-establish the connection)
    /// - `shutdown`
    case ready(ReadyState)

    /// A `Channel` is desired, we'll attempt to create one in the future.
    ///
    /// Valid next states:
    /// - `connecting`
    /// - `shutdown`
    case transientFailure(TransientFailureState)

    /// We never want another `Channel`: this state is terminal.
    case shutdown(ShutdownState)

    fileprivate var label: String {
      switch self {
      case .idle:
        return "idle"
      case .connecting:
        return "connecting"
      case .active:
        return "active"
      case .ready:
        return "ready"
      case .transientFailure:
        return "transientFailure"
      case .shutdown:
        return "shutdown"
      }
    }
  }

  private var state: State {
    didSet {
      switch self.state {
      case .idle:
        self.monitor.updateState(to: .idle, logger: self.logger)
        self.updateConnectionID()

      case .connecting:
        self.monitor.updateState(to: .connecting, logger: self.logger)

      // This is an internal state.
      case .active:
        ()

      case .ready:
        self.monitor.updateState(to: .ready, logger: self.logger)

      case .transientFailure:
        self.monitor.updateState(to: .transientFailure, logger: self.logger)
        self.updateConnectionID()

      case .shutdown:
        self.monitor.updateState(to: .shutdown, logger: self.logger)
      }
    }
  }

  internal let eventLoop: EventLoop
  internal let monitor: ConnectivityStateMonitor
  internal var logger: Logger
  private let configuration: ClientConnection.Configuration

  private let connectionID: String
  private var channelNumber: UInt64
  private var channelNumberLock = Lock()

  private var _connectionIDAndNumber: String {
    return "\(self.connectionID)/\(self.channelNumber)"
  }

  private var connectionIDAndNumber: String {
    return self.channelNumberLock.withLock {
      return self._connectionIDAndNumber
    }
  }

  private func updateConnectionID() {
    self.channelNumberLock.withLockVoid {
      self.channelNumber &+= 1
      self.logger[metadataKey: MetadataKey.connectionID] = "\(self._connectionIDAndNumber)"
    }
  }

  internal func appendMetadata(to logger: inout Logger) {
    logger[metadataKey: MetadataKey.connectionID] = "\(self.connectionIDAndNumber)"
  }

  // Only used for testing.
  private var channelProvider: (() -> EventLoopFuture<Channel>)?

  internal convenience init(configuration: ClientConnection.Configuration, logger: Logger) {
    self.init(configuration: configuration, logger: logger, channelProvider: nil)
  }

  /// Create a `ConnectionManager` for testing: uses the given `channelProvider` to create channels.
  internal static func testingOnly(
    configuration: ClientConnection.Configuration,
    logger: Logger,
    channelProvider: @escaping () -> EventLoopFuture<Channel>
  ) -> ConnectionManager {
    return ConnectionManager(
      configuration: configuration,
      logger: logger,
      channelProvider: channelProvider
    )
  }

  private init(
    configuration: ClientConnection.Configuration,
    logger: Logger,
    channelProvider: (() -> EventLoopFuture<Channel>)?
  ) {
    // Setup the logger.
    var logger = logger
    let connectionID = UUID().uuidString
    let channelNumber: UInt64 = 0
    logger[metadataKey: MetadataKey.connectionID] = "\(connectionID)/\(channelNumber)"

    let eventLoop = configuration.eventLoopGroup.next()
    self.eventLoop = eventLoop
    self.state = .idle
    self.monitor = ConnectivityStateMonitor(
      delegate: configuration.connectivityStateDelegate,
      queue: configuration.connectivityStateDelegateQueue
    )
    self.configuration = configuration

    self.channelProvider = channelProvider

    self.connectionID = connectionID
    self.channelNumber = channelNumber
    self.logger = logger
  }

  /// Get the multiplexer from the underlying channel handling gRPC calls.
  /// if the `ConnectionManager` was configured to be `fastFailure` this will have
  /// one chance to connect - if not reconnections are managed here.
  internal func getHTTP2Multiplexer() -> EventLoopFuture<HTTP2StreamMultiplexer> {
    func getHTTP2Multiplexer0() -> EventLoopFuture<HTTP2StreamMultiplexer> {
      switch self.configuration.callStartBehavior.wrapped {
      case .waitsForConnectivity:
        return self.getHTTP2MultiplexerPatient()
      case .fastFailure:
        return self.getHTTP2MultiplexerOptimistic()
      }
    }

    if self.eventLoop.inEventLoop {
      return getHTTP2Multiplexer0()
    } else {
      return self.eventLoop.flatSubmit {
        getHTTP2Multiplexer0()
      }
    }
  }

  /// Returns a future for the multiplexer which succeeded when the channel is connected.
  /// Reconnects are handled if necessary.
  private func getHTTP2MultiplexerPatient() -> EventLoopFuture<HTTP2StreamMultiplexer> {
    let multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

    switch self.state {
    case .idle:
      self.startConnecting()
      // We started connecting so we must transition to the `connecting` state.
      guard case let .connecting(connecting) = self.state else {
        self.invalidState()
      }
      multiplexer = connecting.readyChannelMuxPromise.futureResult

    case let .connecting(state):
      multiplexer = state.readyChannelMuxPromise.futureResult

    case let .active(state):
      multiplexer = state.readyChannelMuxPromise.futureResult

    case let .ready(state):
      multiplexer = self.eventLoop.makeSucceededFuture(state.multiplexer)

    case let .transientFailure(state):
      multiplexer = state.readyChannelMuxPromise.futureResult

    case let .shutdown(state):
      multiplexer = self.eventLoop.makeFailedFuture(state.reason)
    }

    self.logger.debug("vending multiplexer future", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])

    return multiplexer
  }

  /// Returns a future for the current HTTP/2 stream multiplexer, or future HTTP/2 stream multiplexer from the current connection
  /// attempt, or if the state is 'idle' returns the future for the next connection attempt.
  ///
  /// Note: if the state is 'transientFailure' or 'shutdown' then a failed future will be returned.
  private func getHTTP2MultiplexerOptimistic() -> EventLoopFuture<HTTP2StreamMultiplexer> {
    // `getHTTP2Multiplexer` makes sure we're on the event loop but let's just be sure.
    self.eventLoop.preconditionInEventLoop()

    let muxFuture: EventLoopFuture<HTTP2StreamMultiplexer> = { () in
      switch self.state {
      case .idle:
        self.startConnecting()
        // We started connecting so we must transition to the `connecting` state.
        guard case let .connecting(connecting) = self.state else {
          self.invalidState()
        }
        return connecting.candidateMuxPromise.futureResult
      case let .connecting(state):
        return state.candidateMuxPromise.futureResult
      case let .active(active):
        return self.eventLoop.makeSucceededFuture(active.multiplexer)
      case let .ready(ready):
        return self.eventLoop.makeSucceededFuture(ready.multiplexer)
      case let .transientFailure(state):
        // Provide the reason we failed transiently, if we can.
        let error = state.reason ?? GRPCStatus(
          code: .unavailable,
          message: "Connection multiplexer requested while backing off"
        )
        return self.eventLoop.makeFailedFuture(error)
      case let .shutdown(state):
        return self.eventLoop.makeFailedFuture(state.reason)
      }
    }()

    self.logger.debug("vending fast-failing multiplexer future", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])
    return muxFuture
  }

  /// Shutdown any connection which exists. This is a request from the application.
  internal func shutdown() -> EventLoopFuture<Void> {
    return self.eventLoop.flatSubmit {
      self.logger.debug("shutting down connection", metadata: [
        "connectivity_state": "\(self.state.label)",
      ])
      let shutdown: ShutdownState

      switch self.state {
      // We don't have a channel and we don't want one, easy!
      case .idle:
        shutdown = .shutdownByUser(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

      // We're mid-connection: the application doesn't have any 'ready' channels so we'll succeed
      // the shutdown future and deal with any fallout from the connecting channel without the
      // application knowing.
      case let .connecting(state):
        shutdown = .shutdownByUser(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't have access to the channel or multiplexer.
        state.readyChannelMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))
        state.candidateMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))
        // In case we do successfully connect, close immediately.
        state.candidate.whenSuccess {
          $0.close(mode: .all, promise: nil)
        }

      // We have an active channel but the application doesn't know about it yet. We'll do the same
      // as for `.connecting`.
      case let .active(state):
        shutdown = .shutdownByUser(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't have access to the channel or multiplexer.
        state.readyChannelMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))
        // We have a channel, close it.
        state.candidate.close(mode: .all, promise: nil)

      // The channel is up and running: the application could be using it. We can close it and
      // return the `closeFuture`.
      case let .ready(state):
        shutdown = .shutdownByUser(closeFuture: state.channel.closeFuture)
        self.state = .shutdown(shutdown)

        // We have a channel, close it.
        state.channel.close(mode: .all, promise: nil)

      // Like `.connecting` and `.active` the application does not have a `.ready` channel. We'll
      // do the same but also cancel any scheduled connection attempts and deal with any fallout
      // if we cancelled too late.
      case let .transientFailure(state):
        shutdown = .shutdownByUser(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Stop the creation of a new channel, if we can. If we can't then the task to
        // `startConnecting()` will see our new `shutdown` state and ignore the request to connect.
        state.scheduled.cancel()

        // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't should have access to the channel.
        state.readyChannelMuxPromise.fail(shutdown.reason)

      // We're already shutdown; nothing to do.
      case let .shutdown(state):
        shutdown = state
      }

      return shutdown.closeFuture
    }
  }

  // MARK: - State changes from the channel handler.

  /// The channel caught an error. Hold on to it until the channel becomes inactive, it may provide
  /// some context.
  internal func channelError(_ error: Error) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .idle:
      self.invalidState()

    case .connecting:
      self.invalidState()

    case var .active(state):
      state.error = error
      self.state = .active(state)

    case var .ready(state):
      state.error = error
      self.state = .ready(state)

    // If we've already in one of these states, then additional errors aren't helpful to us.
    case .transientFailure, .shutdown:
      ()
    }
  }

  /// The connecting channel became `active`. Must be called on the `EventLoop`.
  internal func channelActive(channel: Channel, multiplexer: HTTP2StreamMultiplexer) {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug("activating connection", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])

    switch self.state {
    case let .connecting(connecting):
      let connected = ConnectedState(from: connecting, candidate: channel, multiplexer: multiplexer)
      self.state = .active(connected)
      // Optimistic connections are happy this this level of setup.
      connecting.candidateMuxPromise.succeed(multiplexer)

    // Application called shutdown before the channel become active; we should close it.
    case .shutdown:
      channel.close(mode: .all, promise: nil)

    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .idle:
      self.invalidState()

    case .active:
      self.invalidState()

    case .ready:
      self.invalidState()

    case .transientFailure:
      self.invalidState()
    }
  }

  /// An established channel (i.e. `active` or `ready`) has become inactive: should we reconnect?
  /// Must be called on the `EventLoop`.
  internal func channelInactive() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug("deactivating connection", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])

    switch self.state {
    // The channel is `active` but not `ready`. Should we try again?
    case let .active(active):
      let error = GRPCStatus(
        code: .unavailable,
        message: "The connection was dropped and connection re-establishment is disabled"
      )
      switch active.reconnect {
      // No, shutdown instead.
      case .none:
        self.logger.debug("shutting down connection")

        let shutdownState = ShutdownState(
          closeFuture: self.eventLoop.makeSucceededFuture(()),
          reason: error
        )

        self.state = .shutdown(shutdownState)
        active.readyChannelMuxPromise.fail(error)

      // Yes, after some time.
      case let .after(delay):
        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.logger.debug("scheduling connection attempt", metadata: ["delay_secs": "\(delay)"])
        self.state = .transientFailure(TransientFailureState(from: active, scheduled: scheduled))
      }

    // The channel was ready and working fine but something went wrong. Should we try to replace
    // the channel?
    case let .ready(ready):
      // No, no backoff is configured.
      if self.configuration.connectionBackoff == nil {
        self.logger.debug("shutting down connection, no reconnect configured/remaining")
        self.state = .shutdown(
          ShutdownState(
            closeFuture: ready.channel.closeFuture,
            reason: GRPCStatus(
              code: .unavailable,
              message: "The connection was dropped and a reconnect was not configured"
            )
          )
        )
      } else {
        // Yes, start connecting now. We should go via `transientFailure`, however.
        let scheduled = self.eventLoop.scheduleTask(in: .nanoseconds(0)) {
          self.startConnecting()
        }
        self.logger.debug("scheduling connection attempt", metadata: ["delay": "0"])
        let backoffIterator = self.configuration.connectionBackoff?.makeIterator()
        self.state = .transientFailure(TransientFailureState(
          from: ready,
          scheduled: scheduled,
          backoffIterator: backoffIterator
        ))
      }

    // This is fine: we expect the channel to become inactive after becoming idle.
    case .idle:
      ()

    // We're already shutdown, that's fine.
    case .shutdown:
      ()

    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .connecting:
      self.invalidState()

    case .transientFailure:
      self.invalidState()
    }
  }

  /// The channel has become ready, that is, it has seen the initial HTTP/2 SETTINGS frame. Must be
  /// called on the `EventLoop`.
  internal func ready() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug("connection ready", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])

    switch self.state {
    case let .active(connected):
      self.state = .ready(ReadyState(from: connected))
      connected.readyChannelMuxPromise.succeed(connected.multiplexer)

    case .shutdown:
      ()

    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .idle:
      self.invalidState()

    case .transientFailure:
      self.invalidState()

    case .connecting:
      self.invalidState()

    case .ready:
      self.invalidState()
    }
  }

  /// No active RPCs are happening on 'ready' channel: close the channel for now. Must be called on
  /// the `EventLoop`.
  internal func idle() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug("idling connection", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])

    switch self.state {
    case let .active(state):
      // This state is reachable if the keepalive timer fires before we reach the ready state.
      self.state = .idle
      state.readyChannelMuxPromise
        .fail(GRPCStatus(code: .unavailable, message: "Idled before reaching ready state"))

    case .ready:
      self.state = .idle

    case .shutdown:
      // This is expected when the connection is closed by the user: when the channel becomes
      // inactive and there are no outstanding RPCs, 'idle()' will be called instead of
      // 'channelInactive()'.
      ()

    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .idle:
      self.invalidState()

    case .connecting:
      self.invalidState()

    case .transientFailure:
      self.invalidState()
    }
  }
}

extension ConnectionManager {
  // A connection attempt failed; we never established a connection.
  private func connectionFailed(withError error: Error) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case let .connecting(connecting):
      // Should we reconnect?
      switch connecting.reconnect {
      // No, shutdown.
      case .none:
        self.logger.debug("shutting down connection, no reconnect configured/remaining")
        self.state = .shutdown(
          ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()), reason: error)
        )
        connecting.readyChannelMuxPromise.fail(error)
        connecting.candidateMuxPromise.fail(error)

      // Yes, after a delay.
      case let .after(delay):
        self.logger.debug("scheduling connection attempt", metadata: ["delay": "\(delay)"])
        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.state = .transientFailure(
          TransientFailureState(from: connecting, scheduled: scheduled, reason: error)
        )
        // Candidate mux users are not willing to wait.
        connecting.candidateMuxPromise.fail(error)
      }

    // The application must have called shutdown while we were trying to establish a connection
    // which was doomed to fail anyway. That's fine, we can ignore this.
    case .shutdown:
      ()

    // We can't fail to connect if we aren't trying.
    //
    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .idle:
      self.invalidState()

    case .active:
      self.invalidState()

    case .ready:
      self.invalidState()

    case .transientFailure:
      self.invalidState()
    }
  }
}

extension ConnectionManager {
  // Start establishing a connection: we can only do this from the `idle` and `transientFailure`
  // states. Must be called on the `EventLoop`.
  private func startConnecting() {
    switch self.state {
    case .idle:
      let iterator = self.configuration.connectionBackoff?.makeIterator()
      self.startConnecting(
        backoffIterator: iterator,
        muxPromise: self.eventLoop.makePromise()
      )

    case let .transientFailure(pending):
      self.startConnecting(
        backoffIterator: pending.backoffIterator,
        muxPromise: pending.readyChannelMuxPromise
      )

    // We shutdown before a scheduled connection attempt had started.
    case .shutdown:
      ()

    // These cases are purposefully separated: some crash reporting services provide stack traces
    // which don't include the precondition failure message (which contain the invalid state we were
    // in). Keeping the cases separate allows us work out the state from the line number.
    case .connecting:
      self.invalidState()

    case .active:
      self.invalidState()

    case .ready:
      self.invalidState()
    }
  }

  private func startConnecting(
    backoffIterator: ConnectionBackoffIterator?,
    muxPromise: EventLoopPromise<HTTP2StreamMultiplexer>
  ) {
    let timeoutAndBackoff = backoffIterator?.next()

    // We're already on the event loop: submit the connect so it starts after we've made the
    // state change to `.connecting`.
    self.eventLoop.assertInEventLoop()

    let candidate: EventLoopFuture<Channel> = self.eventLoop.flatSubmit {
      let channel = self.makeChannel(
        connectTimeout: timeoutAndBackoff?.timeout
      )
      channel.whenFailure { error in
        self.connectionFailed(withError: error)
      }
      return channel
    }

    // Should we reconnect if the candidate channel fails?
    let reconnect: Reconnect = timeoutAndBackoff.map { .after($0.backoff) } ?? .none
    let connecting = ConnectingState(
      backoffIterator: backoffIterator,
      reconnect: reconnect,
      candidate: candidate,
      readyChannelMuxPromise: muxPromise,
      candidateMuxPromise: self.eventLoop.makePromise()
    )

    self.state = .connecting(connecting)
  }
}

extension ConnectionManager {
  private func invalidState(
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) -> Never {
    preconditionFailure("Invalid state \(self.state) for \(function)", file: file, line: line)
  }
}

extension ConnectionManager {
  private func makeBootstrap(
    connectTimeout: TimeInterval?
  ) -> ClientBootstrapProtocol {
    let serverHostname: String? = self.configuration.tls.flatMap { tls -> String? in
      if let hostnameOverride = tls.hostnameOverride {
        return hostnameOverride
      } else {
        return configuration.target.host
      }
    }.flatMap { hostname in
      if hostname.isIPAddress {
        return nil
      } else {
        return hostname
      }
    }

    let bootstrap = PlatformSupport.makeClientBootstrap(group: self.eventLoop, logger: self.logger)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        let initialized = channel.configureGRPCClient(
          httpTargetWindowSize: self.configuration.httpTargetWindowSize,
          tlsConfiguration: self.configuration.tls?.configuration,
          tlsServerHostname: serverHostname,
          connectionManager: self,
          connectionKeepalive: self.configuration.connectionKeepalive,
          connectionIdleTimeout: self.configuration.connectionIdleTimeout,
          errorDelegate: self.configuration.errorDelegate,
          requiresZeroLengthWriteWorkaround: PlatformSupport.requiresZeroLengthWriteWorkaround(
            group: self.eventLoop,
            hasTLS: self.configuration.tls != nil
          ),
          logger: self.logger
        )

        // Run the debug initializer, if there is one.
        if let debugInitializer = self.configuration.debugChannelInitializer {
          return initialized.flatMap {
            debugInitializer(channel)
          }
        } else {
          return initialized
        }
      }

    if let connectTimeout = connectTimeout {
      return bootstrap.connectTimeout(.seconds(timeInterval: connectTimeout))
    } else {
      return bootstrap
    }
  }

  private func makeChannel(
    connectTimeout: TimeInterval?
  ) -> EventLoopFuture<Channel> {
    if let provider = self.channelProvider {
      return provider()
    } else {
      let bootstrap = self.makeBootstrap(
        connectTimeout: connectTimeout
      )
      return bootstrap.connect(to: self.configuration.target)
    }
  }
}
