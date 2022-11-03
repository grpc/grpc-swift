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
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP2

#if compiler(>=5.6)
// Unchecked because mutable state is always accessed and modified on a particular event loop.
// APIs which _may_ be called from different threads execute onto the correct event loop first.
// APIs which _must_ be called from an exact event loop have preconditions checking that the correct
// event loop is being used.
extension ConnectionManager: @unchecked Sendable {}
#endif // compiler(>=5.6)

@usableFromInline
internal final class ConnectionManager {
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
    var reason: Error

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
      self.reason = state.error ?? GRPCStatus(
        code: .unavailable,
        message: "Unexpected connection drop"
      )
    }

    init(
      from state: ReadyState,
      scheduled: Scheduled<Void>,
      backoffIterator: ConnectionBackoffIterator?
    ) {
      self.backoffIterator = backoffIterator
      self.readyChannelMuxPromise = state.channel.eventLoop.makePromise()
      self.scheduled = scheduled
      self.reason = state.error ?? GRPCStatus(
        code: .unavailable,
        message: "Unexpected connection drop"
      )
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
    case idle(lastError: Error?)

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

  /// The last 'external' state we are in, a subset of the internal state.
  private var externalState: _ConnectivityState = .idle(nil)

  /// Update the external state, potentially notifying a delegate about the change.
  private func updateExternalState(to nextState: _ConnectivityState) {
    if !self.externalState.isSameState(as: nextState) {
      let oldState = self.externalState
      self.externalState = nextState
      self.connectivityDelegate?.connectionStateDidChange(self, from: oldState, to: nextState)
    }
  }

  /// Our current state.
  private var state: State {
    didSet {
      switch self.state {
      case let .idle(error):
        self.updateExternalState(to: .idle(error))
        self.updateConnectionID()

      case .connecting:
        self.updateExternalState(to: .connecting)

      // This is an internal state.
      case .active:
        ()

      case .ready:
        self.updateExternalState(to: .ready)

      case let .transientFailure(state):
        self.updateExternalState(to: .transientFailure(state.reason))
        self.updateConnectionID()

      case .shutdown:
        self.updateExternalState(to: .shutdown)
      }
    }
  }

  /// Returns whether the state is 'idle'.
  private var isIdle: Bool {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .idle:
      return true
    case .connecting, .transientFailure, .active, .ready, .shutdown:
      return false
    }
  }

  /// Returns whether the state is 'shutdown'.
  private var isShutdown: Bool {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .shutdown:
      return true
    case .idle, .connecting, .transientFailure, .active, .ready:
      return false
    }
  }

  /// Returns the `HTTP2StreamMultiplexer` from the 'ready' state or `nil` if it is not available.
  private var multiplexer: HTTP2StreamMultiplexer? {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case let .ready(state):
      return state.multiplexer

    case .idle, .connecting, .transientFailure, .active, .shutdown:
      return nil
    }
  }

  /// The `EventLoop` that the managed connection will run on.
  internal let eventLoop: EventLoop

  /// A delegate for connectivity changes. Executed on the `EventLoop`.
  private var connectivityDelegate: ConnectionManagerConnectivityDelegate?

  /// A delegate for HTTP/2 connection changes. Executed on the `EventLoop`.
  private var http2Delegate: ConnectionManagerHTTP2Delegate?

  /// An `EventLoopFuture<Channel>` provider.
  private let channelProvider: ConnectionManagerChannelProvider

  /// The behavior for starting a call, i.e. how patient is the caller when asking for a
  /// multiplexer.
  private let callStartBehavior: CallStartBehavior.Behavior

  /// The configuration to use when backing off between connection attempts, if reconnection
  /// attempts should be made at all.
  private let connectionBackoff: ConnectionBackoff?

  /// A logger.
  internal var logger: Logger

  private let connectionID: String
  private var channelNumber: UInt64
  private var channelNumberLock = NIOLock()

  private var _connectionIDAndNumber: String {
    return "\(self.connectionID)/\(self.channelNumber)"
  }

  private var connectionIDAndNumber: String {
    return self.channelNumberLock.withLock {
      return self._connectionIDAndNumber
    }
  }

  private func updateConnectionID() {
    self.channelNumberLock.withLock {
      self.channelNumber &+= 1
      self.logger[metadataKey: MetadataKey.connectionID] = "\(self._connectionIDAndNumber)"
    }
  }

  internal func appendMetadata(to logger: inout Logger) {
    logger[metadataKey: MetadataKey.connectionID] = "\(self.connectionIDAndNumber)"
  }

  internal convenience init(
    configuration: ClientConnection.Configuration,
    channelProvider: ConnectionManagerChannelProvider? = nil,
    connectivityDelegate: ConnectionManagerConnectivityDelegate?,
    logger: Logger
  ) {
    self.init(
      eventLoop: configuration.eventLoopGroup.next(),
      channelProvider: channelProvider ?? DefaultChannelProvider(configuration: configuration),
      callStartBehavior: configuration.callStartBehavior.wrapped,
      connectionBackoff: configuration.connectionBackoff,
      connectivityDelegate: connectivityDelegate,
      http2Delegate: nil,
      logger: logger
    )
  }

  internal init(
    eventLoop: EventLoop,
    channelProvider: ConnectionManagerChannelProvider,
    callStartBehavior: CallStartBehavior.Behavior,
    connectionBackoff: ConnectionBackoff?,
    connectivityDelegate: ConnectionManagerConnectivityDelegate?,
    http2Delegate: ConnectionManagerHTTP2Delegate?,
    logger: Logger
  ) {
    // Setup the logger.
    var logger = logger
    let connectionID = UUID().uuidString
    let channelNumber: UInt64 = 0
    logger[metadataKey: MetadataKey.connectionID] = "\(connectionID)/\(channelNumber)"

    self.eventLoop = eventLoop
    self.state = .idle(lastError: nil)

    self.channelProvider = channelProvider
    self.callStartBehavior = callStartBehavior
    self.connectionBackoff = connectionBackoff
    self.connectivityDelegate = connectivityDelegate
    self.http2Delegate = http2Delegate

    self.connectionID = connectionID
    self.channelNumber = channelNumber
    self.logger = logger
  }

  /// Get the multiplexer from the underlying channel handling gRPC calls.
  /// if the `ConnectionManager` was configured to be `fastFailure` this will have
  /// one chance to connect - if not reconnections are managed here.
  internal func getHTTP2Multiplexer() -> EventLoopFuture<HTTP2StreamMultiplexer> {
    func getHTTP2Multiplexer0() -> EventLoopFuture<HTTP2StreamMultiplexer> {
      switch self.callStartBehavior {
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
        return self.eventLoop.makeFailedFuture(state.reason)
      case let .shutdown(state):
        return self.eventLoop.makeFailedFuture(state.reason)
      }
    }()

    self.logger.debug("vending fast-failing multiplexer future", metadata: [
      "connectivity_state": "\(self.state.label)",
    ])
    return muxFuture
  }

  @usableFromInline
  internal enum ShutdownMode {
    /// Closes the underlying channel without waiting for existing RPCs to complete.
    case forceful
    /// Allows running RPCs to run their course before closing the underlying channel. No new
    /// streams may be created.
    case graceful(NIODeadline)
  }

  /// Shutdown the underlying connection.
  ///
  /// - Note: Initiating a `forceful` shutdown after a `graceful` shutdown has no effect.
  internal func shutdown(mode: ShutdownMode) -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.shutdown(mode: mode, promise: promise)
    return promise.futureResult
  }

  /// Shutdown the underlying connection.
  ///
  /// - Note: Initiating a `forceful` shutdown after a `graceful` shutdown has no effect.
  internal func shutdown(mode: ShutdownMode, promise: EventLoopPromise<Void>) {
    if self.eventLoop.inEventLoop {
      self._shutdown(mode: mode, promise: promise)
    } else {
      self.eventLoop.execute {
        self._shutdown(mode: mode, promise: promise)
      }
    }
  }

  private func _shutdown(mode: ShutdownMode, promise: EventLoopPromise<Void>) {
    self.logger.debug("shutting down connection", metadata: [
      "connectivity_state": "\(self.state.label)",
      "shutdown.mode": "\(mode)",
    ])

    switch self.state {
    // We don't have a channel and we don't want one, easy!
    case .idle:
      let shutdown: ShutdownState = .shutdownByUser(closeFuture: promise.futureResult)
      self.state = .shutdown(shutdown)
      promise.succeed(())

    // We're mid-connection: the application doesn't have any 'ready' channels so we'll succeed
    // the shutdown future and deal with any fallout from the connecting channel without the
    // application knowing.
    case let .connecting(state):
      let shutdown: ShutdownState = .shutdownByUser(closeFuture: promise.futureResult)
      self.state = .shutdown(shutdown)

      // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
      // connect the application shouldn't have access to the channel or multiplexer.
      state.readyChannelMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))
      state.candidateMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))

      // Complete the shutdown promise when the connection attempt has completed.
      state.candidate.whenComplete {
        switch $0 {
        case let .success(channel):
          // In case we do successfully connect, close immediately.
          channel.close(mode: .all, promise: nil)
          promise.completeWith(channel.closeFuture.recoveringFromUncleanShutdown())

        case .failure:
          // We failed to connect, that's fine we still shutdown successfully.
          promise.succeed(())
        }
      }

    // We have an active channel but the application doesn't know about it yet. We'll do the same
    // as for `.connecting`.
    case let .active(state):
      let shutdown: ShutdownState = .shutdownByUser(closeFuture: promise.futureResult)
      self.state = .shutdown(shutdown)

      // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
      // connect the application shouldn't have access to the channel or multiplexer.
      state.readyChannelMuxPromise.fail(GRPCStatus(code: .unavailable, message: nil))
      // We have a channel, close it. We only create streams in the ready state so there's no need
      // to quiesce here.
      state.candidate.close(mode: .all, promise: nil)
      promise.completeWith(state.candidate.closeFuture.recoveringFromUncleanShutdown())

    // The channel is up and running: the application could be using it. We can close it and
    // return the `closeFuture`.
    case let .ready(state):
      let shutdown: ShutdownState = .shutdownByUser(closeFuture: promise.futureResult)
      self.state = .shutdown(shutdown)

      switch mode {
      case .forceful:
        // We have a channel, close it.
        state.channel.close(mode: .all, promise: nil)

      case let .graceful(deadline):
        // If we don't close by the deadline forcibly close the channel.
        let scheduledForceClose = state.channel.eventLoop.scheduleTask(deadline: deadline) {
          self.logger.info("shutdown timer expired, forcibly closing connection")
          state.channel.close(mode: .all, promise: nil)
        }

        // Cancel the force close if we close normally first.
        state.channel.closeFuture.whenComplete { _ in
          scheduledForceClose.cancel()
        }

        // Tell the channel to quiesce. It will be picked up by the idle handler which will close
        // the channel when all streams have been closed.
        state.channel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
      }

      // Complete the promise when we eventually close.
      promise.completeWith(state.channel.closeFuture.recoveringFromUncleanShutdown())

    // Like `.connecting` and `.active` the application does not have a `.ready` channel. We'll
    // do the same but also cancel any scheduled connection attempts and deal with any fallout
    // if we cancelled too late.
    case let .transientFailure(state):
      let shutdown: ShutdownState = .shutdownByUser(closeFuture: promise.futureResult)
      self.state = .shutdown(shutdown)

      // Stop the creation of a new channel, if we can. If we can't then the task to
      // `startConnecting()` will see our new `shutdown` state and ignore the request to connect.
      state.scheduled.cancel()

      // Fail the ready channel mux promise: we're shutting down so even if we manage to successfully
      // connect the application shouldn't should have access to the channel.
      state.readyChannelMuxPromise.fail(shutdown.reason)

      // No active channel, so complete the shutdown promise now.
      promise.succeed(())

    // We're already shutdown; there's nothing to do.
    case let .shutdown(state):
      promise.completeWith(state.closeFuture)
    }
  }

  /// Registers a callback which fires when the current active connection is closed.
  ///
  /// If there is a connection, the callback will be invoked with `true` when the connection is
  /// closed. Otherwise the callback is invoked with `false`.
  internal func onCurrentConnectionClose(_ onClose: @escaping (Bool) -> Void) {
    if self.eventLoop.inEventLoop {
      self._onCurrentConnectionClose(onClose)
    } else {
      self.eventLoop.execute {
        self._onCurrentConnectionClose(onClose)
      }
    }
  }

  private func _onCurrentConnectionClose(_ onClose: @escaping (Bool) -> Void) {
    self.eventLoop.assertInEventLoop()

    switch self.state {
    case let .ready(state):
      state.channel.closeFuture.whenComplete { _ in onClose(true) }
    case .idle, .connecting, .active, .transientFailure, .shutdown:
      onClose(false)
    }
  }

  // MARK: - State changes from the channel handler.

  /// The channel caught an error. Hold on to it until the channel becomes inactive, it may provide
  /// some context.
  internal func channelError(_ error: Error) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    // Hitting an error in idle is a surprise, but not really something we do anything about. Either the
    // error is channel fatal, in which case we'll see channelInactive soon (acceptable), or it's not,
    // and future I/O will either fail fast or work. In either case, all we do is log this and move on.
    case .idle:
      self.logger.warning("ignoring unexpected error in idle", metadata: [
        MetadataKey.error: "\(error)",
      ])

    case .connecting:
      self.connectionFailed(withError: error)

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
      switch active.reconnect {
      // No, shutdown instead.
      case .none:
        self.logger.debug("shutting down connection")

        let error = GRPCStatus(
          code: .unavailable,
          message: "The connection was dropped and connection re-establishment is disabled"
        )

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
      if self.connectionBackoff == nil {
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
        let backoffIterator = self.connectionBackoff?.makeIterator()
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
      self.state = .idle(lastError: state.error)
      state.readyChannelMuxPromise
        .fail(GRPCStatus(code: .unavailable, message: "Idled before reaching ready state"))

    case let .ready(state):
      self.state = .idle(lastError: state.error)

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

  internal func streamOpened() {
    self.eventLoop.assertInEventLoop()
    self.http2Delegate?.streamOpened(self)
  }

  internal func streamClosed() {
    self.eventLoop.assertInEventLoop()
    self.http2Delegate?.streamClosed(self)
  }

  internal func maxConcurrentStreamsChanged(_ maxConcurrentStreams: Int) {
    self.eventLoop.assertInEventLoop()
    self.http2Delegate?.receivedSettingsMaxConcurrentStreams(
      self, maxConcurrentStreams: maxConcurrentStreams
    )
  }

  /// The connection has started quiescing: notify the connectivity monitor of this.
  internal func beginQuiescing() {
    self.eventLoop.assertInEventLoop()
    self.connectivityDelegate?.connectionIsQuiescing(self)
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
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .idle:
      let iterator = self.connectionBackoff?.makeIterator()
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
      let channel: EventLoopFuture<Channel> = self.channelProvider.makeChannel(
        managedBy: self,
        onEventLoop: self.eventLoop,
        connectTimeout: timeoutAndBackoff.map { .seconds(timeInterval: $0.timeout) },
        logger: self.logger
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
  /// Returns a synchronous view of the connection manager; each operation requires the caller to be
  /// executing on the same `EventLoop` as the connection manager.
  internal var sync: Sync {
    return Sync(self)
  }

  internal struct Sync {
    private let manager: ConnectionManager

    fileprivate init(_ manager: ConnectionManager) {
      self.manager = manager
    }

    /// A delegate for connectivity changes.
    internal var connectivityDelegate: ConnectionManagerConnectivityDelegate? {
      get {
        self.manager.eventLoop.assertInEventLoop()
        return self.manager.connectivityDelegate
      }
      nonmutating set {
        self.manager.eventLoop.assertInEventLoop()
        self.manager.connectivityDelegate = newValue
      }
    }

    /// A delegate for HTTP/2 connection changes.
    internal var http2Delegate: ConnectionManagerHTTP2Delegate? {
      get {
        self.manager.eventLoop.assertInEventLoop()
        return self.manager.http2Delegate
      }
      nonmutating set {
        self.manager.eventLoop.assertInEventLoop()
        self.manager.http2Delegate = newValue
      }
    }

    /// Returns `true` if the connection is in the idle state.
    internal var isIdle: Bool {
      return self.manager.isIdle
    }

    /// Returne `true` if the connection is in the shutdown state.
    internal var isShutdown: Bool {
      return self.manager.isShutdown
    }

    /// Returns the `multiplexer` from a connection in the `ready` state or `nil` if it is any
    /// other state.
    internal var multiplexer: HTTP2StreamMultiplexer? {
      return self.manager.multiplexer
    }

    // Start establishing a connection. Must only be called when `isIdle` is `true`.
    internal func startConnecting() {
      self.manager.startConnecting()
    }
  }
}

extension ConnectionManager {
  private func invalidState(
    function: StaticString = #function,
    file: StaticString = #fileID,
    line: UInt = #line
  ) -> Never {
    preconditionFailure("Invalid state \(self.state) for \(function)", file: file, line: line)
  }
}
