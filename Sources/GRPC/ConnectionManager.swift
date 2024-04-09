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

// Unchecked because mutable state is always accessed and modified on a particular event loop.
// APIs which _may_ be called from different threads execute onto the correct event loop first.
// APIs which _must_ be called from an exact event loop have preconditions checking that the correct
// event loop is being used.
@usableFromInline
internal final class ConnectionManager: @unchecked Sendable {

  /// Whether the connection managed by this manager should be allowed to go idle and be closed, or
  /// if it should remain open indefinitely even when there are no active streams.
  internal enum IdleBehavior {
    case closeWhenIdleTimeout
    case neverGoIdle
  }

  internal enum Reconnect {
    case none
    case after(TimeInterval)
  }

  internal struct ConnectingState {
    var backoffIterator: ConnectionBackoffIterator?
    var reconnect: Reconnect
    var connectError: Error?

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

    init(from state: ConnectingState, scheduled: Scheduled<Void>, reason: Error?) {
      self.backoffIterator = state.backoffIterator
      self.readyChannelMuxPromise = state.readyChannelMuxPromise
      self.scheduled = scheduled
      self.reason =
        reason
        ?? GRPCStatus(
          code: .unavailable,
          message: "Unexpected connection drop"
        )
    }

    init(from state: ConnectedState, scheduled: Scheduled<Void>) {
      self.backoffIterator = state.backoffIterator
      self.readyChannelMuxPromise = state.readyChannelMuxPromise
      self.scheduled = scheduled
      self.reason =
        state.error
        ?? GRPCStatus(
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
      self.reason =
        state.error
        ?? GRPCStatus(
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

  /// Returns whether the state is 'connecting'.
  private var isConnecting: Bool {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .connecting:
      return true
    case .idle, .transientFailure, .active, .ready, .shutdown:
      return false
    }
  }

  /// Returns whether the state is 'ready'.
  private var isReady: Bool {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .ready:
      return true
    case .idle, .active, .connecting, .transientFailure, .shutdown:
      return false
    }
  }

  /// Returns whether the state is 'ready'.
  private var isTransientFailure: Bool {
    self.eventLoop.assertInEventLoop()
    switch self.state {
    case .transientFailure:
      return true
    case .idle, .connecting, .active, .ready, .shutdown:
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

  /// Whether this connection should be allowed to go idle (and thus be closed when the idle timer fires).
  internal let idleBehavior: IdleBehavior

  /// A logger.
  internal var logger: Logger

  internal let id: ConnectionManagerID
  private var channelNumber: UInt64
  private var channelNumberLock = NIOLock()

  private var _connectionIDAndNumber: String {
    return "\(self.id)/\(self.channelNumber)"
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
    idleBehavior: IdleBehavior,
    logger: Logger
  ) {
    self.init(
      eventLoop: configuration.eventLoopGroup.next(),
      channelProvider: channelProvider ?? DefaultChannelProvider(configuration: configuration),
      callStartBehavior: configuration.callStartBehavior.wrapped,
      idleBehavior: idleBehavior,
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
    idleBehavior: IdleBehavior,
    connectionBackoff: ConnectionBackoff?,
    connectivityDelegate: ConnectionManagerConnectivityDelegate?,
    http2Delegate: ConnectionManagerHTTP2Delegate?,
    logger: Logger
  ) {
    // Setup the logger.
    var logger = logger
    let connectionID = ConnectionManagerID()
    let channelNumber: UInt64 = 0
    logger[metadataKey: MetadataKey.connectionID] = "\(connectionID)/\(channelNumber)"

    self.eventLoop = eventLoop
    self.state = .idle(lastError: nil)

    self.channelProvider = channelProvider
    self.callStartBehavior = callStartBehavior
    self.connectionBackoff = connectionBackoff
    self.connectivityDelegate = connectivityDelegate
    self.http2Delegate = http2Delegate
    self.idleBehavior = idleBehavior

    self.id = connectionID
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
        self.unreachableState()
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

    self.logger.debug(
      "vending multiplexer future",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )

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
          self.unreachableState()
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

    self.logger.debug(
      "vending fast-failing multiplexer future",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )
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
    self.logger.debug(
      "shutting down connection",
      metadata: [
        "connectivity_state": "\(self.state.label)",
        "shutdown.mode": "\(mode)",
      ]
    )

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
          // In case we do successfully connect, close on the next loop tick. When connecting a
          // channel NIO will complete the promise for the channel before firing channel active.
          // That means we may close and fire inactive before active which HTTP/2 will be unhappy
          // about.
          self.eventLoop.execute {
            channel.close(mode: .all, promise: nil)
            promise.completeWith(channel.closeFuture.recoveringFromUncleanShutdown())
          }

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
      self.logger.warning(
        "ignoring unexpected error in idle",
        metadata: [
          MetadataKey.error: "\(error)"
        ]
      )

    case .connecting(var state):
      // Record the error, the channel promise will notify the manager of any error which occurs
      // while connecting. It may be overridden by this error if it contains more relevant
      // information
      if state.connectError == nil {
        state.connectError = error
        self.state = .connecting(state)

        // The pool is only notified of connection errors when the connection transitions to the
        // transient failure state. However, in some cases (i.e. with NIOTS), errors can be thrown
        // during the connect but before the connect times out.
        //
        // This opens up a period of time where you can start a call and have it fail with
        // deadline exceeded (because no connection was available within the configured max
        // wait time for the pool) but without any diagnostic information. The information is
        // available but it hasn't been made available to the pool at that point in time.
        //
        // The delegate can't easily be modified (it's public API) and a new API doesn't make all
        // that much sense so we elect to check whether the delegate is the pool and call it
        // directly.
        if let pool = self.connectivityDelegate as? ConnectionPool {
          pool.sync.updateMostRecentError(error)
        }
      }

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
    self.logger.debug(
      "activating connection",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )

    switch self.state {
    case let .connecting(connecting):
      let connected = ConnectedState(from: connecting, candidate: channel, multiplexer: multiplexer)
      self.state = .active(connected)
      // Optimistic connections are happy this this level of setup.
      connecting.candidateMuxPromise.succeed(multiplexer)

    // Application called shutdown before the channel become active; we should close it.
    case .shutdown:
      channel.close(mode: .all, promise: nil)

    case .idle, .transientFailure:
      // Received a channelActive when not connecting. Can happen if channelActive and
      // channelInactive are reordered. Ignore.
      ()
    case .active, .ready:
      // Received a second 'channelActive', already active so ignore.
      ()
    }
  }

  /// An established channel (i.e. `active` or `ready`) has become inactive: should we reconnect?
  /// Must be called on the `EventLoop`.
  internal func channelInactive() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug(
      "deactivating connection",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )

    switch self.state {
    // We can hit inactive in connecting if we see channelInactive before channelActive; that's not
    // common but we should tolerate it.
    case let .connecting(connecting):
      // Should we try connecting again?
      switch connecting.reconnect {
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
        // Shutting down, so fail the outstanding promises.
        connecting.readyChannelMuxPromise.fail(error)
        connecting.candidateMuxPromise.fail(error)

      // Yes, after some time.
      case let .after(delay):
        let error = GRPCStatus(code: .unavailable, message: "Connection closed while connecting")
        // Fail the candidate mux promise. Keep the 'readyChannelMuxPromise' as we'll try again.
        connecting.candidateMuxPromise.fail(error)

        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.logger.debug("scheduling connection attempt", metadata: ["delay_secs": "\(delay)"])
        self.state = .transientFailure(.init(from: connecting, scheduled: scheduled, reason: nil))
      }

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
        self.state = .transientFailure(
          TransientFailureState(
            from: ready,
            scheduled: scheduled,
            backoffIterator: backoffIterator
          )
        )
      }

    // This is fine: we expect the channel to become inactive after becoming idle.
    case .idle:
      ()

    // We're already shutdown, that's fine.
    case .shutdown:
      ()

    // Received 'channelInactive' twice; fine, ignore.
    case .transientFailure:
      ()
    }
  }

  /// The channel has become ready, that is, it has seen the initial HTTP/2 SETTINGS frame. Must be
  /// called on the `EventLoop`.
  internal func ready() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug(
      "connection ready",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )

    switch self.state {
    case let .active(connected):
      self.state = .ready(ReadyState(from: connected))
      connected.readyChannelMuxPromise.succeed(connected.multiplexer)

    case .shutdown:
      ()

    case .idle, .transientFailure:
      // No connection or connection attempt exists but connection was marked as ready. This is
      // strange. Ignore it in release mode as there's nothing to close and nowehere to fire an
      // error to.
      assertionFailure("received initial HTTP/2 SETTINGS frame in \(self.state.label) state")

    case .connecting:
      // No channel exists to receive initial HTTP/2 SETTINGS frame on... weird. Ignore in release
      // mode.
      assertionFailure("received initial HTTP/2 SETTINGS frame in \(self.state.label) state")

    case .ready:
      // Already received initial HTTP/2 SETTINGS frame; ignore in release mode.
      assertionFailure("received initial HTTP/2 SETTINGS frame in \(self.state.label) state")
    }
  }

  /// No active RPCs are happening on 'ready' channel: close the channel for now. Must be called on
  /// the `EventLoop`.
  internal func idle() {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug(
      "idling connection",
      metadata: [
        "connectivity_state": "\(self.state.label)"
      ]
    )

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

    case .idle, .transientFailure:
      // There's no connection to idle; ignore.
      ()

    case .connecting:
      // The idle watchdog is started when the connection is active, this shouldn't happen
      // in the connecting state. Ignore it in release mode.
      assertionFailure("tried to idle a connection in the \(self.state.label) state")
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
      self,
      maxConcurrentStreams: maxConcurrentStreams
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
      let reportedError: Error
      switch error as? ChannelError {
      case .some(.connectTimeout):
        // A more relevant error may have been caught earlier. Use that in preference to the
        // timeout as it'll likely be more useful.
        reportedError = connecting.connectError ?? error
      default:
        reportedError = error
      }

      // Should we reconnect?
      switch connecting.reconnect {
      // No, shutdown.
      case .none:
        self.logger.debug("shutting down connection, no reconnect configured/remaining")
        self.state = .shutdown(
          ShutdownState(closeFuture: self.eventLoop.makeSucceededFuture(()), reason: reportedError)
        )
        connecting.readyChannelMuxPromise.fail(reportedError)
        connecting.candidateMuxPromise.fail(reportedError)

      // Yes, after a delay.
      case let .after(delay):
        self.logger.debug("scheduling connection attempt", metadata: ["delay": "\(delay)"])
        let scheduled = self.eventLoop.scheduleTask(in: .seconds(timeInterval: delay)) {
          self.startConnecting()
        }
        self.state = .transientFailure(
          TransientFailureState(from: connecting, scheduled: scheduled, reason: reportedError)
        )
        // Candidate mux users are not willing to wait.
        connecting.candidateMuxPromise.fail(reportedError)
      }

    // The application must have called shutdown while we were trying to establish a connection
    // which was doomed to fail anyway. That's fine, we can ignore this.
    case .shutdown:
      ()

    // Connection attempt failed, but no connection attempt is in progress.
    case .idle, .active, .ready, .transientFailure:
      // Nothing we can do other than ignore in release mode.
      assertionFailure("connect promise failed in \(self.state.label) state")
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

      // The iterator produces the connect timeout and the backoff to use for the next attempt. This
      // is unfortunate if retries is set to none because we need to connect timeout but not the
      // backoff yet the iterator will not return a value to us. To workaround this we grab the
      // connect timeout and override it.
      let connectTimeoutOverride: TimeAmount?
      if let backoff = self.connectionBackoff, backoff.retries == .none {
        connectTimeoutOverride = .seconds(timeInterval: backoff.minimumConnectionTimeout)
      } else {
        connectTimeoutOverride = nil
      }

      self.startConnecting(
        backoffIterator: iterator,
        muxPromise: self.eventLoop.makePromise(),
        connectTimeoutOverride: connectTimeoutOverride
      )

    case let .transientFailure(pending):
      self.startConnecting(
        backoffIterator: pending.backoffIterator,
        muxPromise: pending.readyChannelMuxPromise
      )

    // We shutdown before a scheduled connection attempt had started.
    case .shutdown:
      ()

    // We only call startConnecting() if the connection does not exist and after checking what the
    // current state is, so none of these states should be reachable.
    case .connecting:
      self.unreachableState()
    case .active:
      self.unreachableState()
    case .ready:
      self.unreachableState()
    }
  }

  private func startConnecting(
    backoffIterator: ConnectionBackoffIterator?,
    muxPromise: EventLoopPromise<HTTP2StreamMultiplexer>,
    connectTimeoutOverride: TimeAmount? = nil
  ) {
    let timeoutAndBackoff = backoffIterator?.next()

    // We're already on the event loop: submit the connect so it starts after we've made the
    // state change to `.connecting`.
    self.eventLoop.assertInEventLoop()

    let candidate: EventLoopFuture<Channel> = self.eventLoop.flatSubmit {
      let connectTimeout: TimeAmount?
      if let connectTimeoutOverride = connectTimeoutOverride {
        connectTimeout = connectTimeoutOverride
      } else {
        connectTimeout = timeoutAndBackoff.map { TimeAmount.seconds(timeInterval: $0.timeout) }
      }

      let channel: EventLoopFuture<Channel> = self.channelProvider.makeChannel(
        managedBy: self,
        onEventLoop: self.eventLoop,
        connectTimeout: connectTimeout,
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

    /// Returns `true` if the connection is in the connecting state.
    internal var isConnecting: Bool {
      return self.manager.isConnecting
    }

    /// Returns `true` if the connection is in the ready state.
    internal var isReady: Bool {
      return self.manager.isReady
    }

    /// Returns `true` if the connection is in the transient failure state.
    internal var isTransientFailure: Bool {
      return self.manager.isTransientFailure
    }

    /// Returns `true` if the connection is in the shutdown state.
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
  private func unreachableState(
    function: StaticString = #function,
    file: StaticString = #fileID,
    line: UInt = #line
  ) -> Never {
    fatalError("Invalid state \(self.state) for \(function)", file: file, line: line)
  }
}
