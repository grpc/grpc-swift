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
import NIO
import NIOConcurrencyHelpers
import Logging
import Foundation

internal class ConnectionManager {
  internal struct IdleState {
    var configuration: ClientConnection.Configuration
  }

  internal enum Reconnect {
    case none
    case after(TimeInterval)
  }

  internal struct ConnectingState {
    var configuration: ClientConnection.Configuration
    var backoffIterator: ConnectionBackoffIterator?
    var reconnect: Reconnect

    var readyChannelPromise: EventLoopPromise<Channel>
    var candidate: EventLoopFuture<Channel>
  }

  internal struct ConnectedState {
    var configuration: ClientConnection.Configuration
    var backoffIterator: ConnectionBackoffIterator?
    var reconnect: Reconnect

    var readyChannelPromise: EventLoopPromise<Channel>
    var candidate: Channel

    init(from state: ConnectingState, candidate: Channel) {
      self.configuration = state.configuration
      self.backoffIterator = state.backoffIterator
      self.reconnect = state.reconnect
      self.readyChannelPromise = state.readyChannelPromise
      self.candidate = candidate
    }
  }

  internal struct ReadyState {
    var configuration: ClientConnection.Configuration
    var channel: Channel

    init(from state: ConnectedState) {
      self.configuration = state.configuration
      self.channel = state.candidate
    }
  }

  internal struct TransientFailureState {
    var configuration: ClientConnection.Configuration
    var backoffIterator: ConnectionBackoffIterator?
    var readyChannelPromise: EventLoopPromise<Channel>
    var scheduled: Scheduled<Void>

    init(from state: ConnectingState, scheduled: Scheduled<Void>) {
      self.configuration = state.configuration
      self.backoffIterator = state.backoffIterator
      self.readyChannelPromise = state.readyChannelPromise
      self.scheduled = scheduled
    }

    init(from state: ConnectedState, scheduled: Scheduled<Void>) {
      self.configuration = state.configuration
      self.backoffIterator = state.backoffIterator
      self.readyChannelPromise = state.readyChannelPromise
      self.scheduled = scheduled
    }

    init(from state: ReadyState, scheduled: Scheduled<Void>) {
      self.configuration = state.configuration
      self.backoffIterator = state.configuration.connectionBackoff?.makeIterator()
      self.readyChannelPromise = state.channel.eventLoop.makePromise()
      self.scheduled = scheduled
    }
  }

  internal struct ShutdownState {
    var closeFuture: EventLoopFuture<Void>
  }

  internal enum State {
    /// No `Channel` is required.
    ///
    /// Valid next states:
    /// - `connecting`
    /// - `shutdown`
    case idle(IdleState)

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
  }

  private var state: State {
    didSet {
      switch self.state {
      case .idle:
        self.monitor.updateState(to: .idle, logger: self.logger)

        // Create a new id; it'll be used for the *next* channel we create.
        self.channelNumber &+= 1
        self.logger[metadataKey: MetadataKey.connectionID] = "\(self.connectionId)/\(self.channelNumber)"

      case .connecting:
        self.monitor.updateState(to: .connecting, logger: self.logger)

      // This is an internal state.
      case .active:
        ()

      case .ready:
        self.monitor.updateState(to: .ready, logger: self.logger)

      case .transientFailure:
        self.monitor.updateState(to: .transientFailure, logger: self.logger)

      case .shutdown:
        self.monitor.updateState(to: .shutdown, logger: self.logger)
      }
    }
  }

  internal let eventLoop: EventLoop
  internal let monitor: ConnectivityStateMonitor
  internal var logger: Logger

  private let connectionId: String
  private var channelNumber: UInt64

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
    let connectionId = UUID().uuidString
    let channelNumber: UInt64 = 0
    logger[metadataKey: MetadataKey.connectionID] = "\(connectionId)/\(channelNumber)"

    let eventLoop = configuration.eventLoopGroup.next()
    self.eventLoop = eventLoop
    self.state = .idle(IdleState(configuration: configuration))
    self.monitor = ConnectivityStateMonitor(
      delegate: configuration.connectivityStateDelegate,
      queue: configuration.connectivityStateDelegateQueue
    )

    self.channelProvider = channelProvider

    self.connectionId = connectionId
    self.channelNumber = channelNumber
    self.logger = logger
  }

  /// Returns a future for a connected channel.
  internal func getChannel() -> EventLoopFuture<Channel> {
    return self.eventLoop.flatSubmit {
      switch self.state {
      case .idle:
        self.startConnecting()
        // We started connecting so we must transition to the `connecting` state.
        guard case .connecting(let connecting) = self.state else {
          self.invalidState()
        }
        return connecting.readyChannelPromise.futureResult

      case .connecting(let state):
        return state.readyChannelPromise.futureResult

      case .active(let state):
        return state.readyChannelPromise.futureResult

      case .ready(let state):
        return state.channel.eventLoop.makeSucceededFuture(state.channel)

      case .transientFailure(let state):
        return state.readyChannelPromise.futureResult

      case .shutdown:
        return self.eventLoop.makeFailedFuture(GRPCStatus(code: .unavailable, message: nil))
      }
    }
  }

  /// Returns a future for the current channel, or future channel from the current connection
  /// attempt, or if the state is 'idle' returns the future for the next connection attempt.
  ///
  /// Note: if the state is 'transientFailure' or 'shutdown' then a failed future will be returned.
  internal func getOptimisticChannel() -> EventLoopFuture<Channel> {
    return self.eventLoop.flatSubmit {
      switch self.state {
      case .idle:
        self.startConnecting()
        // We started connecting so we must transition to the `connecting` state.
        guard case .connecting(let connecting) = self.state else {
          self.invalidState()
        }
        return connecting.candidate

      case .connecting(let state):
        return state.candidate

      case .active(let state):
        return state.candidate.eventLoop.makeSucceededFuture(state.candidate)

      case .ready(let state):
        return state.channel.eventLoop.makeSucceededFuture(state.channel)

      case .transientFailure:
        return self.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel)

      case .shutdown:
        return self.eventLoop.makeFailedFuture(GRPCStatus(code: .unavailable, message: nil))
      }
    }
  }

  /// Shutdown any connection which exists. This is a request from the application.
  internal func shutdown() -> EventLoopFuture<Void> {
    return self.eventLoop.flatSubmit {
      let shutdown: ShutdownState

      switch self.state {
      // We don't have a channel and we don't want one, easy!
      case .idle:
        shutdown = ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

      // We're mid-connection: the application doesn't have any 'ready' channels so we'll succeed
      // the shutdown future and deal with any fallout from the connecting channel without the
      // application knowing.
      case .connecting(let state):
        shutdown = ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Fail the ready channel promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't should have access to the channel.
        state.readyChannelPromise.fail(GRPCStatus(code: .unavailable, message: nil))
        // In case we do successfully connect, close immediately.
        state.candidate.whenSuccess {
          $0.close(mode: .all, promise: nil)
        }

      // We have an active channel but the application doesn't know about it yet. We'll do the same
      // as for `.connecting`.
      case .active(let state):
        shutdown = ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Fail the ready channel promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't should have access to the channel.
        state.readyChannelPromise.fail(GRPCStatus(code: .unavailable, message: nil))
        // We have a channel, close it.
        state.candidate.close(mode: .all, promise: nil)

      // The channel is up and running: the application could be using it. We can close it and
      // return the `closeFuture`.
      case .ready(let state):
        shutdown = ShutdownState(closeFuture: state.channel.closeFuture)
        self.state = .shutdown(shutdown)

        // We have a channel, close it.
        state.channel.close(mode: .all, promise: nil)

      // Like `.connecting` and `.active` the application does not have a `.ready` channel. We'll
      // do the same but also cancel any scheduled connection attempts and deal with any fallout
      // if we cancelled too late.
      case .transientFailure(let state):
        // Stop the creation of a new channel, if we can. If we can't then the task to
        // `startConnecting()` will see our new `shutdown` state and ignore the request to connect.
        state.scheduled.cancel()
        shutdown = ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()))
        self.state = .shutdown(shutdown)

        // Fail the ready channel promise: we're shutting down so even if we manage to successfully
        // connect the application shouldn't should have access to the channel.
        state.readyChannelPromise.fail(GRPCStatus(code: .unavailable, message: nil))

      // We're already shutdown; nothing to do.
      case .shutdown(let state):
        shutdown = state
      }

      return shutdown.closeFuture
    }
  }

  // MARK: - State changes from the channel handler.

  /// The connecting channel became `active`. Must be called on the `EventLoop`.
  internal func channelActive(channel: Channel) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .connecting(let connecting):
      self.state = .active(ConnectedState(from: connecting, candidate: channel))

    // Application called shutdown before the channel become active; we should close it.
    case .shutdown:
      channel.close(mode: .all, promise: nil)

    case .idle, .active, .ready, .transientFailure:
      self.invalidState()
    }
  }

  /// An established channel (i.e. `active` or `ready`) has become inactive: should we reconnect?
  /// Must be called on the `EventLoop`.
  internal func channelInactive() {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    // The channel is `active` but not `ready`. Should we try again?
    case .active(let active):
      switch active.reconnect {
      // No, shutdown instead.
      case .none:
        self.state = .shutdown(ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(())))
        active.readyChannelPromise.fail(GRPCStatus(code: .unavailable, message: nil))

      // Yes, after some time.
      case .after(let delay):
        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.state = .transientFailure(TransientFailureState(from: active, scheduled: scheduled))
      }

    // The channel was ready and working fine but something went wrong. Should we try to replace
    // the channel?
    case .ready(let ready):
      // No, no backoff is configured.
      if ready.configuration.connectionBackoff == nil {
        self.state = .shutdown(ShutdownState(closeFuture: ready.channel.closeFuture))
      } else {
        // Yes, start connecting now. We should go via `transientFailure`, however.
        let scheduled = self.eventLoop.scheduleTask(in: .nanoseconds(0)) {
          self.startConnecting()
        }
        self.state = .transientFailure(TransientFailureState(from: ready, scheduled: scheduled))
      }

    // This is fine: we expect the channel to become inactive after becoming idle.
    case .idle:
      ()

    // We're already shutdown, that's fine.
    case .shutdown:
      ()

    case .connecting, .transientFailure:
      self.invalidState()
    }
  }

  /// The channel has become ready, that is, it has seen the initial HTTP/2 SETTINGS frame. Must be
  /// called on the `EventLoop`.
  internal func ready() {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .active(let connected):
      self.state = .ready(ReadyState(from: connected))
      connected.readyChannelPromise.succeed(connected.candidate)

    case .shutdown:
      ()

    case .idle, .transientFailure, .connecting, .ready:
      self.invalidState()
    }
  }

  /// No active RPCs are happening on 'ready' channel: close the channel for now. Must be called on
  /// the `EventLoop`.
  internal func idle() {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .ready(let state):
      self.state = .idle(IdleState(configuration: state.configuration))

    case .idle, .connecting, .transientFailure, .active, .shutdown:
      self.invalidState()
    }
  }
}

extension ConnectionManager {
  // A connection attempt failed; we never established a connection.
  private func connectionFailed(withError error: Error) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .connecting(let connecting):
      // Should we reconnect?
      switch connecting.reconnect {
      // No, shutdown.
      case .none:
        connecting.readyChannelPromise.fail(error)
        self.state = .shutdown(ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(())))

      // Yes, after a delay.
      case .after(let delay):
        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.state = .transientFailure(TransientFailureState(from: connecting, scheduled: scheduled))
      }

    // The application must have called shutdown while we were trying to establish a connection
    // which was doomed to fail anyway. That's fine, we can ignore this.
    case .shutdown:
      ()

    // We can't fail to connect if we aren't trying.
    case .idle, .active, .ready, .transientFailure:
      self.invalidState()
    }
  }
}

extension ConnectionManager {
  // Start establishing a connection: we can only do this from the `idle` and `transientFailure`
  // states. Must be called on the `EventLoop`.
  private func startConnecting() {
    switch self.state {
    case .idle(let state):
      let iterator = state.configuration.connectionBackoff?.makeIterator()
      self.startConnecting(
        configuration: state.configuration,
        backoffIterator: iterator,
        channelPromise: self.eventLoop.makePromise()
      )

    case .transientFailure(let pending):
      self.startConnecting(
        configuration: pending.configuration,
        backoffIterator: pending.backoffIterator,
        channelPromise: pending.readyChannelPromise
      )

    // We shutdown before a scheduled connection attempt had started.
    case .shutdown:
      ()

    case .connecting, .active, .ready:
      self.invalidState()
    }
  }

  private func startConnecting(
    configuration: ClientConnection.Configuration,
    backoffIterator: ConnectionBackoffIterator?,
    channelPromise: EventLoopPromise<Channel>
  ) {
    let timeoutAndBackoff = backoffIterator?.next()

    // We're already on the event loop: submit the connect so it starts after we've made the
    // state change to `.connecting`.
    self.eventLoop.assertInEventLoop()

    let candidate: EventLoopFuture<Channel> = self.eventLoop.flatSubmit {
      let channel = self.makeChannel(
        configuration: configuration,
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
      configuration: configuration,
      backoffIterator: backoffIterator,
      reconnect: reconnect,
      readyChannelPromise: channelPromise,
      candidate: candidate
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
    configuration: ClientConnection.Configuration,
    connectTimeout: TimeInterval?
  ) -> ClientBootstrapProtocol {
    let serverHostname: String? = configuration.tls.flatMap { tls -> String? in
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
        channel.configureGRPCClient(
          httpTargetWindowSize: configuration.httpTargetWindowSize,
          tlsConfiguration: configuration.tls?.configuration,
          tlsServerHostname: serverHostname,
          connectionManager: self,
          connectionIdleTimeout: configuration.connectionIdleTimeout,
          errorDelegate: configuration.errorDelegate,
          logger: self.logger
        )
      }

    if let connectTimeout = connectTimeout {
      return bootstrap.connectTimeout(.seconds(timeInterval: connectTimeout))
    } else {
      return bootstrap
    }
  }

  private func makeChannel(
    configuration: ClientConnection.Configuration,
    connectTimeout: TimeInterval?
  ) -> EventLoopFuture<Channel> {
    if let provider = self.channelProvider {
      return provider()
    } else {
      let bootstrap = self.makeBootstrap(
        configuration: configuration,
        connectTimeout: connectTimeout
      )
      return bootstrap.connect(to: configuration.target)
    }
  }
}
