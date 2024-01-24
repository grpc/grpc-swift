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

import NIOCore
import NIOHTTP2

extension ServerConnectionManagementHandler {
  /// Tracks the state of TCP connections at the server.
  ///
  /// The state machine manages the state for the graceful shutdown procedure as well as policing
  /// client-side keep alive.
  struct StateMachine {
    /// Current state.
    private var state: State

    /// Opaque data sent to the client in a PING frame after emitting the first GOAWAY frame
    /// as part of graceful shutdown.
    private let goAwayPingData: HTTP2PingData

    /// Create a new state machine.
    ///
    /// - Parameters:
    ///   - allowKeepAliveWithoutCalls: Whether the client is permitted to send keep alive pings
    ///       when there are no active calls.
    ///   - minPingReceiveIntervalWithoutCalls: The minimum time interval required between keep
    ///       alive pings when there are no active calls.
    ///   - goAwayPingData: Opaque data sent to the client in a PING frame when the server
    ///       initiates graceful shutdown.
    init(
      allowKeepAliveWithoutCalls: Bool,
      minPingReceiveIntervalWithoutCalls: TimeAmount,
      goAwayPingData: HTTP2PingData = HTTP2PingData(withInteger: .random(in: .min ... .max))
    ) {
      let keepAlive = KeepAlive(
        allowWithoutCalls: allowKeepAliveWithoutCalls,
        minPingReceiveIntervalWithoutCalls: minPingReceiveIntervalWithoutCalls
      )

      self.state = .active(State.Active(keepAlive: keepAlive))
      self.goAwayPingData = goAwayPingData
    }

    /// Record that the stream with the given ID has been opened.
    mutating func streamOpened(_ id: HTTP2StreamID) {
      switch self.state {
      case .active(var state):
        state.lastStreamID = id
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .active(state)

      case .closing(var state):
        state.lastStreamID = id
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .closing(state)

      case .closed:
        ()
      }
    }

    enum OnStreamClosed: Equatable {
      /// Start the idle timer, after which the connection should be closed gracefully.
      case startIdleTimer
      /// Close the connection.
      case close
      /// Do nothing.
      case none
    }

    /// Record that the stream with the given ID has been closed.
    mutating func streamClosed(_ id: HTTP2StreamID) -> OnStreamClosed {
      let onStreamClosed: OnStreamClosed

      switch self.state {
      case .active(var state):
        let removedID = state.openStreams.remove(id)
        assert(removedID != nil, "Can't close stream \(Int(id)), it wasn't open")
        onStreamClosed = state.openStreams.isEmpty ? .startIdleTimer : .none
        self.state = .active(state)

      case .closing(var state):
        let removedID = state.openStreams.remove(id)
        assert(removedID != nil, "Can't close stream \(Int(id)), it wasn't open")
        // If the second GOAWAY hasn't been sent it isn't safe to close if there are no open
        // streams: the client may have opened a stream which the server doesn't know about yet.
        let canClose = state.sentSecondGoAway && state.openStreams.isEmpty
        onStreamClosed = canClose ? .close : .none
        self.state = .closing(state)

      case .closed:
        onStreamClosed = .none
      }

      return onStreamClosed
    }

    enum OnPing: Equatable {
      /// Send a GOAWAY frame with the code "enhance your calm" and immediately close the connection.
      case enhanceYourCalmThenClose(HTTP2StreamID)
      /// Acknowledge the ping.
      case sendAck
      /// Ignore the ping.
      case none
    }

    /// Received a ping with the given data.
    ///
    /// - Parameters:
    ///   - time: The time at which the ping was received.
    ///   - data: The data sent with the ping.
    mutating func receivedPing(atTime time: NIODeadline, data: HTTP2PingData) -> OnPing {
      let onPing: OnPing

      switch self.state {
      case .active(var state):
        let tooManyPings = state.keepAlive.receivedPing(
          atTime: time,
          hasOpenStreams: !state.openStreams.isEmpty
        )

        if tooManyPings {
          onPing = .enhanceYourCalmThenClose(state.lastStreamID)
          self.state = .closed
        } else {
          onPing = .sendAck
          self.state = .active(state)
        }

      case .closing(var state):
        let tooManyPings = state.keepAlive.receivedPing(
          atTime: time,
          hasOpenStreams: !state.openStreams.isEmpty
        )

        if tooManyPings {
          onPing = .enhanceYourCalmThenClose(state.lastStreamID)
          self.state = .closed
        } else {
          onPing = .sendAck
          self.state = .closing(state)
        }

      case .closed:
        onPing = .none
      }

      return onPing
    }

    enum OnPingAck: Equatable {
      /// Send a GOAWAY frame with no error and the given last stream ID, optionally closing the
      /// connection immediately afterwards.
      case sendGoAway(lastStreamID: HTTP2StreamID, close: Bool)
      /// Ignore the ack.
      case none
    }

    /// Received a PING frame with the 'ack' flag set.
    mutating func receivedPingAck(data: HTTP2PingData) -> OnPingAck {
      let onPingAck: OnPingAck

      switch self.state {
      case .closing(var state):
        // If only one GOAWAY has been sent and the data matches the data from the GOAWAY ping then
        // the server should send another GOAWAY ratcheting down the last stream ID. If no streams
        // are open then the server can close the connection immediately after, otherwise it must
        // wait until all streams are closed.
        if !state.sentSecondGoAway, data == self.goAwayPingData {
          state.sentSecondGoAway = true

          if state.openStreams.isEmpty {
            self.state = .closed
            onPingAck = .sendGoAway(lastStreamID: state.lastStreamID, close: true)
          } else {
            self.state = .closing(state)
            onPingAck = .sendGoAway(lastStreamID: state.lastStreamID, close: false)
          }
        } else {
          onPingAck = .none
        }

      case .active, .closed:
        onPingAck = .none
      }

      return onPingAck
    }

    enum OnStartGracefulShutdown: Equatable {
      /// Initiate graceful shutdown by sending a GOAWAY frame with the last stream ID set as the max
      /// stream ID and no error. Follow it immediately with a PING frame with the given data.
      case sendGoAwayAndPing(HTTP2PingData)
      /// Ignore the request to start graceful shutdown.
      case none
    }

    /// Request that the connection begins graceful shutdown.
    mutating func startGracefulShutdown() -> OnStartGracefulShutdown {
      let onStartGracefulShutdown: OnStartGracefulShutdown

      switch self.state {
      case .active(let state):
        self.state = .closing(State.Closing(from: state))
        onStartGracefulShutdown = .sendGoAwayAndPing(self.goAwayPingData)

      case .closing, .closed:
        onStartGracefulShutdown = .none
      }

      return onStartGracefulShutdown
    }

    /// Reset the state of keep-alive policing.
    mutating func resetKeepAliveState() {
      switch self.state {
      case .active(var state):
        state.keepAlive.reset()
        self.state = .active(state)

      case .closing(var state):
        state.keepAlive.reset()
        self.state = .closing(state)

      case .closed:
        ()
      }
    }

    /// Marks the state as closed.
    mutating func markClosed() {
      self.state = .closed
    }
  }
}

extension ServerConnectionManagementHandler.StateMachine {
  fileprivate struct KeepAlive {
    /// Allow the client to send keep alive pings when there are no active calls.
    private let allowWithoutCalls: Bool

    /// The minimum time interval which pings may be received at when there are no active calls.
    private let minPingReceiveIntervalWithoutCalls: TimeAmount

    /// The maximum number of "bad" pings sent by the client the server tolerates before closing
    /// the connection.
    private let maxPingStrikes: Int

    /// The number of "bad" pings sent by the client. This can be reset when the server sends
    /// DATA or HEADERS frames.
    ///
    /// Ping strikes account for pings being occasionally being used for purposes other than keep
    /// alive (a low number of strikes is therefore expected and okay).
    private var pingStrikes: Int

    /// The last time a valid ping happened.
    ///
    /// Note: `distantPast` isn't used to indicate no previous valid ping as `NIODeadline` uses
    /// the monotonic clock on Linux which uses an undefined starting point and in some cases isn't
    /// always that distant.
    private var lastValidPingTime: NIODeadline?

    init(allowWithoutCalls: Bool, minPingReceiveIntervalWithoutCalls: TimeAmount) {
      self.allowWithoutCalls = allowWithoutCalls
      self.minPingReceiveIntervalWithoutCalls = minPingReceiveIntervalWithoutCalls
      self.maxPingStrikes = 2
      self.pingStrikes = 0
      self.lastValidPingTime = nil
    }

    /// Reset ping strikes and the time of the last valid ping.
    mutating func reset() {
      self.lastValidPingTime = nil
      self.pingStrikes = 0
    }

    /// Returns whether the client has sent too many pings.
    mutating func receivedPing(atTime time: NIODeadline, hasOpenStreams: Bool) -> Bool {
      let interval: TimeAmount

      if hasOpenStreams || self.allowWithoutCalls {
        interval = self.minPingReceiveIntervalWithoutCalls
      } else {
        // If there are no open streams and keep alive pings aren't allowed without calls then
        // use an interval of two hours.
        //
        // This comes from gRFC A8: https://github.com/grpc/proposal/blob/master/A8-client-side-keepalive.md
        interval = .hours(2)
      }

      // If there's no last ping time then the first is acceptable.
      let isAcceptablePing = self.lastValidPingTime.map { $0 + interval <= time } ?? true
      let tooManyPings: Bool

      if isAcceptablePing {
        self.lastValidPingTime = time
        tooManyPings = false
      } else {
        self.pingStrikes += 1
        tooManyPings = self.pingStrikes > self.maxPingStrikes
      }

      return tooManyPings
    }
  }
}

extension ServerConnectionManagementHandler.StateMachine {
  fileprivate enum State {
    /// The connection is active.
    struct Active {
      /// The number of open streams.
      var openStreams: Set<HTTP2StreamID>
      /// The ID of the most recently opened stream (zero indicates no streams have been opened yet).
      var lastStreamID: HTTP2StreamID
      /// The state of keep alive.
      var keepAlive: KeepAlive

      init(keepAlive: KeepAlive) {
        self.openStreams = []
        self.lastStreamID = .rootStream
        self.keepAlive = keepAlive
      }
    }

    /// The connection is closing gracefully, an initial GOAWAY frame has been sent (with the
    /// last stream ID set to max).
    struct Closing {
      /// The number of open streams.
      var openStreams: Set<HTTP2StreamID>
      /// The ID of the most recently opened stream (zero indicates no streams have been opened yet).
      var lastStreamID: HTTP2StreamID
      /// The state of keep alive.
      var keepAlive: KeepAlive
      /// Whether the second GOAWAY frame has been sent with a lower stream ID.
      var sentSecondGoAway: Bool

      init(from state: Active) {
        self.openStreams = state.openStreams
        self.lastStreamID = state.lastStreamID
        self.keepAlive = state.keepAlive
        self.sentSecondGoAway = false
      }
    }

    case active(Active)
    case closing(Closing)
    case closed
  }
}
