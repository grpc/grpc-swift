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
import Logging
import NIOCore
import NIOHTTP2

/// Holds state for the 'GRPCIdleHandler', this isn't really just the idleness of the connection,
/// it also holds state relevant to quiescing the connection as well as logging some HTTP/2 specific
/// information (like stream creation/close events and changes to settings which can be useful when
/// debugging live systems). Much of this information around the connection state is also used to
/// inform the client connection manager since that's strongly tied to various channel and HTTP/2
/// events.
struct GRPCIdleHandlerStateMachine {
  /// Our role in the connection.
  enum Role {
    case server
    case client
  }

  /// The 'operating' state of the connection. This is the primary state we expect to be in: the
  /// connection is up and running and there are expected to be active RPCs, although this is by no
  /// means a requirement. Some of the situations in which there may be no active RPCs are:
  ///
  /// 1. Before the connection is 'ready' (that is, seen the first SETTINGS frame),
  /// 2. After the connection has dropped to zero active streams and before the idle timeout task
  ///    has been scheduled.
  /// 3. When the connection has zero active streams and the connection was configured without an
  ///    idle timeout.
  fileprivate struct Operating: CanOpenStreams, CanCloseStreams {
    /// Our role in the connection.
    var role: Role

    /// The number of open stream.
    var openStreams: Int

    /// The last stream ID initiated by the remote peer.
    var lastPeerInitiatedStreamID: HTTP2StreamID

    /// The maximum number of concurrent streams we are allowed to operate.
    var maxConcurrentStreams: Int

    /// We keep track of whether we've seen a SETTINGS frame. We expect to see one after the
    /// connection preface (RFC 7540 § 3.5). This is primarily for the benefit of the client which
    /// determines a connection to be 'ready' once it has seen the first SETTINGS frame. We also
    /// won't set an idle timeout until this becomes true.
    var hasSeenSettings: Bool

    fileprivate init(role: Role) {
      self.role = role
      self.openStreams = 0
      self.lastPeerInitiatedStreamID = .rootStream
      // Assumed until we know better.
      self.maxConcurrentStreams = 100
      self.hasSeenSettings = false
    }

    fileprivate init(fromWaitingToIdle state: WaitingToIdle) {
      self.role = state.role
      self.openStreams = 0
      self.lastPeerInitiatedStreamID = state.lastPeerInitiatedStreamID
      self.maxConcurrentStreams = state.maxConcurrentStreams
      // We won't transition to 'WaitingToIdle' unless we've seen a SETTINGS frame.
      self.hasSeenSettings = true
    }
  }

  /// The waiting-to-idle state is used when the connection has become 'ready', has no active
  /// RPCs and an idle timeout task has been scheduled. In this state, the connection will be closed
  /// once the idle is fired. The task will be cancelled on the creation of a stream.
  fileprivate struct WaitingToIdle {
    /// Our role in the connection.
    var role: Role

    /// The last stream ID initiated by the remote peer.
    var lastPeerInitiatedStreamID: HTTP2StreamID

    /// The maximum number of concurrent streams we are allowed to operate.
    var maxConcurrentStreams: Int

    /// A task which, when fired, will idle the connection.
    var idleTask: Scheduled<Void>

    fileprivate init(fromOperating state: Operating, idleTask: Scheduled<Void>) {
      // We won't transition to this state unless we've seen a SETTINGS frame.
      assert(state.hasSeenSettings)

      self.role = state.role
      self.lastPeerInitiatedStreamID = state.lastPeerInitiatedStreamID
      self.maxConcurrentStreams = state.maxConcurrentStreams
      self.idleTask = idleTask
    }
  }

  /// The quiescing state is entered only from the operating state. It may be entered if we receive
  /// a GOAWAY frame (the remote peer initiated the quiescing) or we initiate graceful shutdown
  /// locally.
  fileprivate struct Quiescing: TracksOpenStreams, CanCloseStreams {
    /// Our role in the connection.
    var role: Role

    /// The number of open stream.
    var openStreams: Int

    /// The last stream ID initiated by the remote peer.
    var lastPeerInitiatedStreamID: HTTP2StreamID

    /// The maximum number of concurrent streams we are allowed to operate.
    var maxConcurrentStreams: Int

    /// Whether this peer initiated shutting down.
    var initiatedByUs: Bool

    fileprivate init(fromOperating state: Operating, initiatedByUs: Bool) {
      // If we didn't initiate shutdown, the remote peer must have done so by sending a GOAWAY frame
      // in which case we must have seen a SETTINGS frame.
      assert(initiatedByUs || state.hasSeenSettings)
      self.role = state.role
      self.initiatedByUs = initiatedByUs
      self.openStreams = state.openStreams
      self.lastPeerInitiatedStreamID = state.lastPeerInitiatedStreamID
      self.maxConcurrentStreams = state.maxConcurrentStreams
    }
  }

  /// The closing state is entered when one of the previous states initiates a connection closure.
  /// From this state the only possible transition is to the closed state.
  fileprivate struct Closing {
    /// Our role in the connection.
    var role: Role

    /// Should the client connection manager receive an idle event when we close? (If not then it
    /// will attempt to establish a new connection immediately.)
    var shouldIdle: Bool

    fileprivate init(fromOperating state: Operating) {
      self.role = state.role
      // Idle if there are no open streams and we've seen the first SETTINGS frame.
      self.shouldIdle = !state.hasOpenStreams && state.hasSeenSettings
    }

    fileprivate init(fromQuiescing state: Quiescing) {
      self.role = state.role
      // If we initiated the quiescing then we shouldn't go idle (we want to shutdown instead).
      self.shouldIdle = !state.initiatedByUs
    }

    fileprivate init(fromWaitingToIdle state: WaitingToIdle, shouldIdle: Bool = true) {
      self.role = state.role
      self.shouldIdle = shouldIdle
    }
  }

  fileprivate enum State {
    case operating(Operating)
    case waitingToIdle(WaitingToIdle)
    case quiescing(Quiescing)
    case closing(Closing)
    case closed
  }

  /// The set of operations that should be performed as a result of interaction with the state
  /// machine.
  struct Operations {
    /// An event to notify the connection manager about.
    private(set) var connectionManagerEvent: ConnectionManagerEvent?

    /// The value of HTTP/2 SETTINGS_MAX_CONCURRENT_STREAMS changed.
    private(set) var maxConcurrentStreamsChange: Int?

    /// An idle task, either scheduling or cancelling an idle timeout.
    private(set) var idleTask: IdleTask?

    /// Send a GOAWAY frame with the last peer initiated stream ID set to this value.
    private(set) var sendGoAwayWithLastPeerInitiatedStreamID: HTTP2StreamID?

    /// Whether the channel should be closed.
    private(set) var shouldCloseChannel: Bool

    /// Whether a ping should be sent after a GOAWAY frame.
    private(set) var shouldPingAfterGoAway: Bool

    fileprivate static let none = Operations()

    fileprivate mutating func sendGoAwayFrame(
      lastPeerInitiatedStreamID streamID: HTTP2StreamID,
      followWithPing: Bool = false
    ) {
      self.sendGoAwayWithLastPeerInitiatedStreamID = streamID
      self.shouldPingAfterGoAway = followWithPing
    }

    fileprivate mutating func cancelIdleTask(_ task: Scheduled<Void>) {
      self.idleTask = .cancel(task)
    }

    fileprivate mutating func scheduleIdleTask() {
      self.idleTask = .schedule
    }

    fileprivate mutating func closeChannel() {
      self.shouldCloseChannel = true
    }

    fileprivate mutating func notifyConnectionManager(about event: ConnectionManagerEvent) {
      self.connectionManagerEvent = event
    }

    fileprivate mutating func maxConcurrentStreamsChanged(_ newValue: Int) {
      self.maxConcurrentStreamsChange = newValue
    }

    private init() {
      self.connectionManagerEvent = nil
      self.idleTask = nil
      self.sendGoAwayWithLastPeerInitiatedStreamID = nil
      self.shouldCloseChannel = false
      self.shouldPingAfterGoAway = false
    }
  }

  /// An event to notify the 'ConnectionManager' about.
  enum ConnectionManagerEvent {
    case inactive
    case idle
    case ready
    case quiescing
  }

  enum IdleTask {
    case schedule
    case cancel(Scheduled<Void>)
  }

  /// The current state.
  private var state: State

  /// A logger.
  internal var logger: Logger

  /// Create a new state machine.
  init(role: Role, logger: Logger) {
    self.state = .operating(.init(role: role))
    self.logger = logger
  }

  // MARK: Stream Events

  /// An HTTP/2 stream was created.
  mutating func streamCreated(withID streamID: HTTP2StreamID) -> Operations {
    var operations: Operations = .none

    switch self.state {
    case var .operating(state):
      // Create the stream.
      state.streamCreated(streamID, logger: self.logger)
      self.state = .operating(state)

    case let .waitingToIdle(state):
      var operating = Operating(fromWaitingToIdle: state)
      operating.streamCreated(streamID, logger: self.logger)
      self.state = .operating(operating)
      operations.cancelIdleTask(state.idleTask)

    case var .quiescing(state):
      state.lastPeerInitiatedStreamID = streamID
      state.openStreams += 1
      self.state = .quiescing(state)

    case .closing, .closed:
      ()
    }

    return operations
  }

  /// An HTTP/2 stream was closed.
  mutating func streamClosed(withID streamID: HTTP2StreamID) -> Operations {
    var operations: Operations = .none

    switch self.state {
    case var .operating(state):
      state.streamClosed(streamID, logger: self.logger)

      if state.hasSeenSettings, !state.hasOpenStreams {
        operations.scheduleIdleTask()
      }

      self.state = .operating(state)

    case .waitingToIdle:
      // If we're waiting to idle then there can't be any streams open which can be closed.
      preconditionFailure()

    case var .quiescing(state):
      state.streamClosed(streamID, logger: self.logger)

      if state.hasOpenStreams {
        self.state = .quiescing(state)
      } else {
        self.state = .closing(.init(fromQuiescing: state))
        operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
        operations.closeChannel()
      }

    case .closing, .closed:
      ()
    }

    return operations
  }

  // MARK: - Idle Events

  /// The given task was scheduled to idle the connection.
  mutating func scheduledIdleTimeoutTask(_ task: Scheduled<Void>) -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .operating(state):
      if state.hasOpenStreams {
        operations.cancelIdleTask(task)
      } else {
        self.state = .waitingToIdle(.init(fromOperating: state, idleTask: task))
      }

    case .waitingToIdle:
      // There's already an idle task.
      preconditionFailure()

    case .quiescing, .closing, .closed:
      operations.cancelIdleTask(task)
    }

    return operations
  }

  /// The idle timeout task fired, the connection should be idled.
  mutating func idleTimeoutTaskFired() -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .waitingToIdle(state):
      self.state = .closing(.init(fromWaitingToIdle: state))
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
      operations.closeChannel()

    // We're either operating on streams, streams are going away, or the connection is going away
    // so we don't need to idle the connection.
    case .operating, .quiescing, .closing, .closed:
      ()
    }

    return operations
  }

  // MARK: - Shutdown Events

  /// Close the connection, this can be caused as a result of a keepalive timeout (i.e. the server
  /// has become unresponsive), we'll bin this connection as a result.
  mutating func shutdownNow() -> Operations {
    var operations = Operations.none

    switch self.state {
    case let .operating(state):
      var closing = Closing(fromOperating: state)
      closing.shouldIdle = false
      self.state = .closing(closing)
      operations.closeChannel()
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)

    case let .waitingToIdle(state):
      // Don't idle.
      self.state = .closing(Closing(fromWaitingToIdle: state, shouldIdle: false))
      operations.closeChannel()
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
      operations.cancelIdleTask(state.idleTask)

    case let .quiescing(state):
      self.state = .closing(Closing(fromQuiescing: state))
      // We've already sent a GOAWAY frame if we're in this state, just close.
      operations.closeChannel()

    case .closing, .closed:
      ()
    }

    return operations
  }

  /// Initiate a graceful shutdown of this connection, that is, begin quiescing.
  mutating func initiateGracefulShutdown() -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .operating(state):
      if state.hasOpenStreams {
        // There are open streams: send a GOAWAY frame and wait for the stream count to reach zero.
        //
        // It's okay if we haven't seen a SETTINGS frame at this point; we've initiated the shutdown
        // so making a connection is ready isn't necessary.
        operations.notifyConnectionManager(about: .quiescing)

        // TODO: we should ratchet down the last initiated stream after 1-RTT.
        //
        // As a client we will just stop initiating streams.
        if state.role == .server {
          operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
        }

        self.state = .quiescing(.init(fromOperating: state, initiatedByUs: true))
      } else {
        // No open streams: send a GOAWAY frame and close the channel.
        self.state = .closing(.init(fromOperating: state))
        operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
        operations.closeChannel()
      }

    case let .waitingToIdle(state):
      // There can't be any open streams, but we have a few loose ends to clear up: we need to
      // cancel the idle timeout, send a GOAWAY frame and then close. We don't want to idle from the
      // closing state: we want to shutdown instead.
      self.state = .closing(.init(fromWaitingToIdle: state, shouldIdle: false))
      operations.cancelIdleTask(state.idleTask)
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
      operations.closeChannel()

    case var .quiescing(state):
      // We're already quiescing: either the remote initiated it or we're initiating it more than
      // once. Set ourselves as the initiator to ensure we don't idle when we eventually close, this
      // is important for the client: if the server initiated this then we establish a new
      // connection when we close, unless we also initiated shutdown.
      state.initiatedByUs = true
      self.state = .quiescing(state)

    case var .closing(state):
      // We've already called 'close()', make sure we don't go idle.
      state.shouldIdle = false
      self.state = .closing(state)

    case .closed:
      ()
    }

    return operations
  }

  /// We've received a GOAWAY frame from the remote peer. Either the remote peer wants to close the
  /// connection or they're responding to us shutting down the connection.
  mutating func receiveGoAway() -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .operating(state):
      // A SETTINGS frame MUST follow the connection preface. (RFC 7540 § 3.5)
      assert(state.hasSeenSettings)

      if state.hasOpenStreams {
        operations.notifyConnectionManager(about: .quiescing)
        switch state.role {
        case .client:
          // The server sent us a GOAWAY we'll just stop opening new streams and will send a GOAWAY
          // frame before we close later.
          ()
        case .server:
          // Client sent us a GOAWAY frame; we'll let the streams drain and then close. We'll tell
          // the client that we're going away and send them a ping. When we receive the pong we will
          // send another GOAWAY frame with a lower stream ID. In this case, the pong acts as an ack
          // for the GOAWAY.
          operations.sendGoAwayFrame(lastPeerInitiatedStreamID: .maxID, followWithPing: true)
        }
        self.state = .quiescing(.init(fromOperating: state, initiatedByUs: false))
      } else {
        // No open streams, we can close as well.
        self.state = .closing(.init(fromOperating: state))
        operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
        operations.closeChannel()
      }

    case let .waitingToIdle(state):
      // There can't be any open streams, but we have a few loose ends to clear up: we need to
      // cancel the idle timeout, send a GOAWAY frame and then close.
      self.state = .closing(.init(fromWaitingToIdle: state))
      operations.cancelIdleTask(state.idleTask)
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: state.lastPeerInitiatedStreamID)
      operations.closeChannel()

    case .quiescing:
      // We're already quiescing, this changes nothing.
      ()

    case .closing, .closed:
      // We're already closing/closed (so must have emitted a GOAWAY frame already). Ignore this.
      ()
    }

    return operations
  }

  mutating func ratchetDownGoAwayStreamID() -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .quiescing(state):
      let streamID = state.lastPeerInitiatedStreamID
      operations.sendGoAwayFrame(lastPeerInitiatedStreamID: streamID)
    case .operating, .waitingToIdle:
      // We can only ratchet down the stream ID if we're already quiescing.
      preconditionFailure()
    case .closing, .closed:
      ()
    }

    return operations
  }

  mutating func receiveSettings(_ settings: HTTP2Settings) -> Operations {
    // Log the change in settings.
    self.logger.debug(
      "HTTP2 settings update",
      metadata: Dictionary(settings.map {
        ("\($0.parameter.loggingMetadataKey)", "\($0.value)")
      }, uniquingKeysWith: { a, _ in a })
    )

    var operations: Operations = .none

    switch self.state {
    case var .operating(state):
      let hasSeenSettingsPreviously = state.hasSeenSettings

      // If we hadn't previously seen settings then we need to notify the client connection manager
      // that we're now ready.
      if !hasSeenSettingsPreviously {
        operations.notifyConnectionManager(about: .ready)
        state.hasSeenSettings = true

        // Now that we know the connection is ready, we may want to start an idle timeout as well.
        if !state.hasOpenStreams {
          operations.scheduleIdleTask()
        }
      }

      // Update max concurrent streams.
      if let maxStreams = settings.last(where: { $0.parameter == .maxConcurrentStreams })?.value {
        operations.maxConcurrentStreamsChanged(maxStreams)
        state.maxConcurrentStreams = maxStreams
      } else if !hasSeenSettingsPreviously {
        // We hadn't seen settings before now and max concurrent streams wasn't set we should assume
        // the default and emit an update.
        operations.maxConcurrentStreamsChanged(100)
        state.maxConcurrentStreams = 100
      }

      self.state = .operating(state)

    case var .waitingToIdle(state):
      // Update max concurrent streams.
      if let maxStreams = settings.last(where: { $0.parameter == .maxConcurrentStreams })?.value {
        operations.maxConcurrentStreamsChanged(maxStreams)
        state.maxConcurrentStreams = maxStreams
      }
      self.state = .waitingToIdle(state)

    case .quiescing, .closing, .closed:
      ()
    }

    return operations
  }

  // MARK: - Channel Events

  // (Other channel events aren't included here as they don't impact the state machine.)

  /// 'channelActive' was called in the idle handler holding this state machine.
  mutating func channelInactive() -> Operations {
    var operations: Operations = .none

    switch self.state {
    case let .operating(state):
      self.state = .closed

      // We unexpectedly became inactive.
      if !state.hasSeenSettings || state.hasOpenStreams {
        // Haven't seen settings, or we've seen settings and there are open streams.
        operations.notifyConnectionManager(about: .inactive)
      } else {
        // Have seen settings and there are no open streams.
        operations.notifyConnectionManager(about: .idle)
      }

    case let .waitingToIdle(state):
      self.state = .closed

      // We were going to idle anyway.
      operations.notifyConnectionManager(about: .idle)
      operations.cancelIdleTask(state.idleTask)

    case let .quiescing(state):
      self.state = .closed

      if state.initiatedByUs || state.hasOpenStreams {
        operations.notifyConnectionManager(about: .inactive)
      } else {
        operations.notifyConnectionManager(about: .idle)
      }

    case let .closing(state):
      self.state = .closed

      if state.shouldIdle {
        operations.notifyConnectionManager(about: .idle)
      } else {
        operations.notifyConnectionManager(about: .inactive)
      }

    case .closed:
      ()
    }

    return operations
  }
}

// MARK: - Helper Protocols

private protocol TracksOpenStreams {
  /// The number of open streams.
  var openStreams: Int { get set }
}

extension TracksOpenStreams {
  /// Whether any streams are open.
  fileprivate var hasOpenStreams: Bool {
    return self.openStreams != 0
  }
}

private protocol CanOpenStreams: TracksOpenStreams {
  /// The role of this peer in the connection.
  var role: GRPCIdleHandlerStateMachine.Role { get }

  /// The ID of the stream most recently initiated by the remote peer.
  var lastPeerInitiatedStreamID: HTTP2StreamID { get set }

  /// The maximum number of concurrent streams.
  var maxConcurrentStreams: Int { get set }

  mutating func streamCreated(_ streamID: HTTP2StreamID, logger: Logger)
}

extension CanOpenStreams {
  fileprivate mutating func streamCreated(_ streamID: HTTP2StreamID, logger: Logger) {
    self.openStreams += 1

    switch self.role {
    case .client where streamID.isServerInitiated:
      self.lastPeerInitiatedStreamID = streamID
    case .server where streamID.isClientInitiated:
      self.lastPeerInitiatedStreamID = streamID
    default:
      ()
    }

    logger.debug("HTTP2 stream created", metadata: [
      MetadataKey.h2StreamID: "\(streamID)",
      MetadataKey.h2ActiveStreams: "\(self.openStreams)",
    ])

    if self.openStreams == self.maxConcurrentStreams {
      logger.warning("HTTP2 max concurrent stream limit reached", metadata: [
        MetadataKey.h2ActiveStreams: "\(self.openStreams)",
      ])
    }
  }
}

private protocol CanCloseStreams: TracksOpenStreams {
  /// Notes that a stream has closed.
  mutating func streamClosed(_ streamID: HTTP2StreamID, logger: Logger)
}

extension CanCloseStreams {
  fileprivate mutating func streamClosed(_ streamID: HTTP2StreamID, logger: Logger) {
    self.openStreams -= 1

    logger.debug("HTTP2 stream closed", metadata: [
      MetadataKey.h2StreamID: "\(streamID)",
      MetadataKey.h2ActiveStreams: "\(self.openStreams)",
    ])
  }
}
