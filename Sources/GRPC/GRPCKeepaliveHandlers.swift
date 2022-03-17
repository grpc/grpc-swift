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
import NIOCore
import NIOHTTP2

struct PingHandler {
  /// Opaque ping data used for keep-alive pings.
  private let pingData: HTTP2PingData

  /// Opaque ping data used for a ping sent after a GOAWAY frame.
  internal let pingDataGoAway: HTTP2PingData

  /// The amount of time to wait before sending a keepalive ping.
  private let interval: TimeAmount

  /// The amount of time to wait for an acknowledgment.
  /// If it does not receive an acknowledgment within this time, it will close the connection
  private let timeout: TimeAmount

  /// Send keepalive pings even if there are no calls in flight.
  private let permitWithoutCalls: Bool

  /// Maximum number of pings that can be sent when there is no data/header frame to be sent.
  private let maximumPingsWithoutData: UInt

  /// If there are no data/header frames being received:
  /// The minimum amount of time to wait between successive pings.
  private let minimumSentPingIntervalWithoutData: TimeAmount

  /// If there are no data/header frames being sent:
  /// The minimum amount of time expected between receiving successive pings.
  /// If the time between successive pings is less than this value, then the ping will be considered a bad ping from the peer.
  /// Such a ping counts as a "ping strike".
  /// Ping strikes are only applicable to server handler
  private let minimumReceivedPingIntervalWithoutData: TimeAmount?

  /// Maximum number of bad pings that the server will tolerate before sending an HTTP2 GOAWAY frame and closing the connection.
  /// Setting it to `0` allows the server to accept any number of bad pings.
  /// Ping strikes are only applicable to server handler
  private let maximumPingStrikes: UInt?

  /// When the handler started pinging
  private var startedAt: NIODeadline?

  /// When the last ping was received
  private var lastReceivedPingDate: NIODeadline?

  /// When the last ping was sent
  private var lastSentPingDate: NIODeadline?

  /// The number of pings sent on the transport without any data
  private var sentPingsWithoutData = 0

  /// Number of strikes
  private var pingStrikes: UInt = 0

  /// The scheduled task which will close the connection.
  private var scheduledClose: Scheduled<Void>?

  /// Number of active streams
  private var activeStreams = 0 {
    didSet {
      if self.activeStreams > 0 {
        self.sentPingsWithoutData = 0
      }
    }
  }

  private static let goAwayFrame = HTTP2Frame.FramePayload.goAway(
    lastStreamID: .rootStream,
    errorCode: .enhanceYourCalm,
    opaqueData: nil
  )

  // For testing only
  var _testingOnlyNow: NIODeadline?

  enum Action {
    case none
    case schedulePing(delay: TimeAmount, timeout: TimeAmount)
    case cancelScheduledTimeout
    case reply(HTTP2Frame.FramePayload)
    case ratchetDownLastSeenStreamID
  }

  init(
    pingCode: UInt64,
    interval: TimeAmount,
    timeout: TimeAmount,
    permitWithoutCalls: Bool,
    maximumPingsWithoutData: UInt,
    minimumSentPingIntervalWithoutData: TimeAmount,
    minimumReceivedPingIntervalWithoutData: TimeAmount? = nil,
    maximumPingStrikes: UInt? = nil
  ) {
    self.pingData = HTTP2PingData(withInteger: pingCode)
    self.pingDataGoAway = HTTP2PingData(withInteger: ~pingCode)
    self.interval = interval
    self.timeout = timeout
    self.permitWithoutCalls = permitWithoutCalls
    self.maximumPingsWithoutData = maximumPingsWithoutData
    self.minimumSentPingIntervalWithoutData = minimumSentPingIntervalWithoutData
    self.minimumReceivedPingIntervalWithoutData = minimumReceivedPingIntervalWithoutData
    self.maximumPingStrikes = maximumPingStrikes
  }

  mutating func streamCreated() -> Action {
    self.activeStreams += 1

    if self.startedAt == nil {
      self.startedAt = self.now()
      return .schedulePing(delay: self.interval, timeout: self.timeout)
    } else {
      return .none
    }
  }

  mutating func streamClosed() -> Action {
    self.activeStreams -= 1
    return .none
  }

  mutating func read(pingData: HTTP2PingData, ack: Bool) -> Action {
    if ack {
      return self.handlePong(pingData)
    } else {
      return self.handlePing(pingData)
    }
  }

  private func handlePong(_ pingData: HTTP2PingData) -> Action {
    if pingData == self.pingData {
      return .cancelScheduledTimeout
    } else if pingData == self.pingDataGoAway {
      // We received a pong for a ping we sent to trail a GOAWAY frame: this means we can now
      // send another GOAWAY frame with a (possibly) lower stream ID.
      return .ratchetDownLastSeenStreamID
    } else {
      return .none
    }
  }

  private mutating func handlePing(_ pingData: HTTP2PingData) -> Action {
    // Do we support ping strikes (only servers support ping strikes)?
    if let maximumPingStrikes = self.maximumPingStrikes {
      // Is this a ping strike?
      if self.isPingStrike {
        self.pingStrikes += 1

        // A maximum ping strike of zero indicates that we tolerate any number of strikes.
        if maximumPingStrikes != 0, self.pingStrikes > maximumPingStrikes {
          return .reply(PingHandler.goAwayFrame)
        } else {
          return .none
        }
      } else {
        // This is a valid ping, reset our strike count and reply with a pong.
        self.pingStrikes = 0
        self.lastReceivedPingDate = self.now()
        return .reply(self.generatePingFrame(data: pingData, ack: true))
      }
    } else {
      // We don't support ping strikes. We'll just reply with a pong.
      //
      // Note: we don't need to update `pingStrikes` or `lastReceivedPingDate` as we don't
      // support ping strikes.
      return .reply(self.generatePingFrame(data: pingData, ack: true))
    }
  }

  mutating func pingFired() -> Action {
    if self.shouldBlockPing {
      return .none
    } else {
      return .reply(self.generatePingFrame(data: self.pingData, ack: false))
    }
  }

  private mutating func generatePingFrame(
    data: HTTP2PingData,
    ack: Bool
  ) -> HTTP2Frame.FramePayload {
    if self.activeStreams == 0 {
      self.sentPingsWithoutData += 1
    }

    self.lastSentPingDate = self.now()
    return HTTP2Frame.FramePayload.ping(data, ack: ack)
  }

  /// Returns true if, on receipt of a ping, the ping should be regarded as a ping strike.
  ///
  /// A ping is considered a 'strike' if:
  /// - There are no active streams.
  /// - We allow pings to be sent when there are no active streams (i.e. `self.permitWithoutCalls`).
  /// - The time since the last ping we received is less than the minimum allowed interval.
  ///
  /// - Precondition: Ping strikes are supported (i.e. `self.maximumPingStrikes != nil`)
  private var isPingStrike: Bool {
    assert(
      self.maximumPingStrikes != nil,
      "Ping strikes are not supported but we're checking for one"
    )
    guard self.activeStreams == 0, self.permitWithoutCalls,
      let lastReceivedPingDate = self.lastReceivedPingDate,
      let minimumReceivedPingIntervalWithoutData = self.minimumReceivedPingIntervalWithoutData
    else {
      return false
    }

    return self.now() - lastReceivedPingDate < minimumReceivedPingIntervalWithoutData
  }

  private var shouldBlockPing: Bool {
    // There is no active call on the transport and pings should not be sent
    guard self.activeStreams > 0 || self.permitWithoutCalls else {
      return true
    }

    // There is no active call on the transport but pings should be sent
    if self.activeStreams == 0, self.permitWithoutCalls {
      // The number of pings already sent on the transport without any data has already exceeded the limit
      if self.sentPingsWithoutData > self.maximumPingsWithoutData {
        return true
      }

      // The time elapsed since the previous ping is less than the minimum required
      if let lastSentPingDate = self.lastSentPingDate,
        self.now() - lastSentPingDate < self.minimumSentPingIntervalWithoutData {
        return true
      }

      return false
    }

    return false
  }

  private func now() -> NIODeadline {
    return self._testingOnlyNow ?? .now()
  }
}
