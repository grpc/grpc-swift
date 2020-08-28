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
import NIOHTTP2

/// Provides keepalive pings.
///
/// The logic is determined by the gRPC keepalive
/// [documentation] (https://github.com/grpc/grpc/blob/master/doc/keepalive.md).
internal class GRPCClientKeepaliveHandler: ChannelInboundHandler, _ChannelKeepaliveHandler {
  typealias InboundIn = HTTP2Frame
  typealias OutboundOut = HTTP2Frame

  init(configuration: ClientConnectionKeepalive) {
    self.pingHandler = PingHandler(
      pingCode: 5,
      interval: configuration.interval,
      timeout: configuration.timeout,
      permitWithoutCalls: configuration.permitWithoutCalls,
      maximumPingsWithoutData: configuration.maximumPingsWithoutData,
      minimumSentPingIntervalWithoutData: configuration.minimumSentPingIntervalWithoutData
    )
  }

  /// The ping handler.
  var pingHandler: PingHandler

  /// The scheduled task which will ping.
  var scheduledPing: RepeatedTask?

  /// The scheduled task which will close the connection.
  var scheduledClose: Scheduled<Void>?
}

internal class GRPCServerKeepaliveHandler: ChannelInboundHandler, _ChannelKeepaliveHandler {
  typealias InboundIn = HTTP2Frame
  typealias OutboundOut = HTTP2Frame

  init(configuration: ServerConnectionKeepalive) {
    self.pingHandler = PingHandler(
      pingCode: 10,
      interval: configuration.interval,
      timeout: configuration.timeout,
      permitWithoutCalls: configuration.permitWithoutCalls,
      maximumPingsWithoutData: configuration.maximumPingsWithoutData,
      minimumSentPingIntervalWithoutData: configuration.minimumSentPingIntervalWithoutData,
      minimumReceivedPingIntervalWithoutData: configuration.minimumReceivedPingIntervalWithoutData,
      maximumPingStrikes: configuration.maximumPingStrikes
    )
  }

  /// The ping handler.
  var pingHandler: PingHandler

  /// The scheduled task which will ping.
  var scheduledPing: RepeatedTask?

  /// The scheduled task which will close the connection.
  var scheduledClose: Scheduled<Void>?
}

protocol _ChannelKeepaliveHandler: ChannelInboundHandler where OutboundOut == HTTP2Frame,
  InboundIn == HTTP2Frame {
  var pingHandler: PingHandler { get set }
  var scheduledPing: RepeatedTask? { get set }
  var scheduledClose: Scheduled<Void>? { get set }
}

extension _ChannelKeepaliveHandler {
  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if event is NIOHTTP2StreamCreatedEvent {
      self.perform(action: self.pingHandler.streamCreated(), context: context)
    } else if event is StreamClosedEvent {
      self.perform(action: self.pingHandler.streamClosed(), context: context)
    }

    context.fireUserInboundEventTriggered(event)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data).payload {
    case let .ping(pingData, ack: ack):
      self.perform(action: self.pingHandler.read(pingData: pingData, ack: ack), context: context)
    default:
      break
    }

    context.fireChannelRead(data)
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.cancelScheduledPing()
    self.cancelScheduledTimeout()
    context.fireChannelInactive()
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.cancelScheduledPing()
    self.cancelScheduledTimeout()
  }

  private func perform(action: PingHandler.Action, context: ChannelHandlerContext) {
    switch action {
    case let .schedulePing(delay, timeout):
      self.schedulePing(delay: delay, timeout: timeout, context: context)
    case .cancelScheduledTimeout:
      self.cancelScheduledTimeout()
    case let .reply(payload):
      self.send(payload: payload, context: context)
    case .none:
      break
    }
  }

  private func send(payload: HTTP2Frame.FramePayload, context: ChannelHandlerContext) {
    let frame = self.wrapOutboundOut(.init(streamID: .rootStream, payload: payload))
    context.writeAndFlush(frame, promise: nil)
  }

  private func schedulePing(delay: TimeAmount, timeout: TimeAmount,
                            context: ChannelHandlerContext) {
    guard delay != .nanoseconds(Int64.max) else { return }

    self.scheduledPing = context.eventLoop
      .scheduleRepeatedTask(initialDelay: delay, delay: delay) { _ in
        self.perform(action: self.pingHandler.pingFired(), context: context)
        // `timeout` is less than `interval`, guaranteeing that the close task
        // will be fired before a new ping is triggered.
        assert(timeout < delay, "`timeout` must be less than `interval`")
        self.scheduleClose(timeout: timeout, context: context)
      }
  }

  private func scheduleClose(timeout: TimeAmount, context: ChannelHandlerContext) {
    self.scheduledClose = context.eventLoop.scheduleTask(in: timeout) {
      context.fireUserInboundEventTriggered(ConnectionIdledEvent())
    }
  }

  private func cancelScheduledPing() {
    self.scheduledPing?.cancel()
    self.scheduledPing = nil
  }

  private func cancelScheduledTimeout() {
    self.scheduledClose?.cancel()
    self.scheduledClose = nil
  }
}

struct PingHandler {
  /// Code for ping
  private let pingCode: UInt64

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
    errorCode: .enhanceYourCalm, opaqueData: nil
  )

  // For testing only
  var _testingOnlyNow: NIODeadline?

  enum Action {
    case none
    case schedulePing(delay: TimeAmount, timeout: TimeAmount)
    case cancelScheduledTimeout
    case reply(HTTP2Frame.FramePayload)
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
    self.pingCode = pingCode
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
    if pingData.integer == self.pingCode {
      return .cancelScheduledTimeout
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
        return .reply(self.generatePingFrame(code: pingData.integer, ack: true))
      }
    } else {
      // We don't support ping strikes. We'll just reply with a pong.
      //
      // Note: we don't need to update `pingStrikes` or `lastReceivedPingDate` as we don't
      // support ping strikes.
      return .reply(self.generatePingFrame(code: pingData.integer, ack: true))
    }
  }

  mutating func pingFired() -> Action {
    if self.shouldBlockPing {
      return .none
    } else {
      return .reply(self.generatePingFrame(code: self.pingCode, ack: false))
    }
  }

  private mutating func generatePingFrame(code: UInt64, ack: Bool) -> HTTP2Frame.FramePayload {
    if self.activeStreams == 0 {
      self.sentPingsWithoutData += 1
    }

    self.lastSentPingDate = self.now()
    return HTTP2Frame.FramePayload.ping(HTTP2PingData(withInteger: code), ack: ack)
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
