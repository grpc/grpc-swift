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

/// A `ChannelHandler` which manages the lifecycle of a gRPC connection over HTTP/2.
///
/// This handler is responsible for managing several aspects of the connection. These include:
/// 1. Handling the graceful close of connections. When gracefully closing a connection the server
///    sends a GOAWAY frame with the last stream ID set to the maximum stream ID allowed followed by
///    a PING frame. On receipt of the PING frame the server sends another GOAWAY frame with the
///    highest ID of all streams which have been opened. After this, the handler closes the
///    connection once all streams are closed.
/// 2. Enforcing that graceful shutdown doesn't exceed a configured limit (if configured).
/// 3. Gracefully closing the connection once it reaches the maximum configured age (if configured).
/// 4. Gracefully closing the connection once it has been idle for a given period of time (if
///    configured).
/// 5. Periodically sending keep alive pings to the client (if configured) and closing the
///    connection if necessary.
/// 6. Policing pings sent by the client to ensure that the client isn't misconfigured to send
///    too many pings.
///
/// Some of the behaviours are described in:
/// - [gRFC A8](https://github.com/grpc/proposal/blob/master/A8-client-side-keepalive.md), and
/// - [gRFC A9](https://github.com/grpc/proposal/blob/master/A9-server-side-conn-mgt.md).
final class ServerConnectionManagementHandler: ChannelDuplexHandler {
  typealias InboundIn = HTTP2Frame
  typealias InboundOut = HTTP2Frame
  typealias OutboundIn = HTTP2Frame
  typealias OutboundOut = HTTP2Frame

  /// The `EventLoop` of the `Channel` this handler exists in.
  private let eventLoop: EventLoop

  /// The maximum amount of time a connection may be idle for. If the connection remains idle
  /// (i.e. has no open streams) for this period of time then the connection will be gracefully
  /// closed.
  private var maxIdleTimer: Timer?

  /// The maximum age of a connection. If the connection remains open after this amount of time
  /// then it will be gracefully closed.
  private var maxAgeTimer: Timer?

  /// The maximum amount of time a connection may spend closing gracefully, after which it is
  /// closed abruptly. The timer starts after the second GOAWAY frame has been sent.
  private var maxGraceTimer: Timer?

  /// The amount of time to wait before sending a keep alive ping.
  private var keepAliveTimer: Timer?

  /// The amount of time the client has to reply after sending a keep alive ping. Only used if
  /// `keepAliveTimer` is set.
  private var keepAliveTimeoutTimer: Timer

  /// Opaque data sent in keep alive pings.
  private let keepAlivePingData: HTTP2PingData

  /// Whether a flush is pending.
  private var flushPending: Bool
  /// Whether `channelRead` has been called and `channelReadComplete` hasn't yet been called.
  /// Resets once `channelReadComplete` returns.
  private var inReadLoop: Bool

  /// The current state of the connection.
  private var state: StateMachine

  /// The clock.
  private let clock: Clock

  /// A clock providing the current time.
  ///
  /// This is necessary for testing where a manual clock can be used and advanced from the test.
  /// While NIO's `EmbeddedEventLoop` provides control over its view of time (and therefore any
  /// events scheduled on it) it doesn't offer a way to get the current time. This is usually done
  /// via `NIODeadline`.
  enum Clock {
    case nio
    case manual(Manual)

    func now() -> NIODeadline {
      switch self {
      case .nio:
        return .now()
      case .manual(let clock):
        return clock.time
      }
    }

    final class Manual {
      private(set) var time: NIODeadline

      init() {
        self.time = .uptimeNanoseconds(0)
      }

      func advance(by amount: TimeAmount) {
        self.time = self.time + amount
      }
    }
  }

  /// Stats about recently written frames. Used to determine whether to reset keep-alive state.
  private var frameStats: FrameStats

  struct FrameStats {
    private(set) var didWriteHeadersOrData = false

    /// Mark that a HEADERS frame has been written.
    mutating func wroteHeaders() {
      self.didWriteHeadersOrData = true
    }

    /// Mark that DATA frame has been written.
    mutating func wroteData() {
      self.didWriteHeadersOrData = true
    }

    /// Resets the state such that no HEADERS or DATA frames have been written.
    mutating func reset() {
      self.didWriteHeadersOrData = false
    }
  }

  /// A synchronous view over this handler.
  var syncView: SyncView {
    return SyncView(self)
  }

  /// A synchronous view over this handler.
  ///
  /// Methods on this view *must* be called from the same `EventLoop` as the `Channel` in which
  /// this handler exists.
  struct SyncView {
    private let handler: ServerConnectionManagementHandler

    fileprivate init(_ handler: ServerConnectionManagementHandler) {
      self.handler = handler
    }

    /// Notify the handler that the connection has received a flush event.
    func connectionWillFlush() {
      // The handler can't rely on `flush(context:)` due to its expected position in the pipeline.
      // It's expected to be placed after the HTTP/2 handler (i.e. closer to the application) as
      // it needs to receive HTTP/2 frames. However, flushes from stream channels aren't sent down
      // the entire connection channel, instead they are sent from the point in the channel they
      // are multiplexed from (either the HTTP/2 handler or the HTTP/2 multiplexing handler,
      // depending on how multiplexing is configured).
      self.handler.eventLoop.assertInEventLoop()
      if self.handler.frameStats.didWriteHeadersOrData {
        self.handler.frameStats.reset()
        self.handler.state.resetKeepAliveState()
      }
    }

    /// Notify the handler that a HEADERS frame was written in the last write loop.
    func wroteHeadersFrame() {
      self.handler.eventLoop.assertInEventLoop()
      self.handler.frameStats.wroteHeaders()
    }

    /// Notify the handler that a DATA frame was written in the last write loop.
    func wroteDataFrame() {
      self.handler.eventLoop.assertInEventLoop()
      self.handler.frameStats.wroteData()
    }
  }

  /// Creates a new handler which manages the lifecycle of a connection.
  ///
  /// - Parameters:
  ///   - eventLoop: The `EventLoop` of the `Channel` this handler is placed in.
  ///   - maxIdleTime: The maximum amount time a connection may be idle for before being closed.
  ///   - maxAge: The maximum amount of time a connection may exist before being gracefully closed.
  ///   - maxGraceTime: The maximum amount of time that the connection has to close gracefully.
  ///   - keepAliveTime: The amount of time to wait after reading data before sending a keep-alive
  ///       ping.
  ///   - keepAliveTimeout: The amount of time the client has to reply after the server sends a
  ///       keep-alive ping to keep the connection open. The connection is closed if no reply
  ///       is received.
  ///   - allowKeepAliveWithoutCalls: Whether the server allows the client to send keep-alive pings
  ///       when there are no calls in progress.
  ///   - minPingIntervalWithoutCalls: The minimum allowed interval the client is allowed to send
  ///       keep-alive pings. Pings more frequent than this interval count as 'strikes' and the
  ///       connection is closed if there are too many strikes.
  ///   - clock: A clock providing the current time.
  init(
    eventLoop: EventLoop,
    maxIdleTime: TimeAmount?,
    maxAge: TimeAmount?,
    maxGraceTime: TimeAmount?,
    keepAliveTime: TimeAmount?,
    keepAliveTimeout: TimeAmount?,
    allowKeepAliveWithoutCalls: Bool,
    minPingIntervalWithoutCalls: TimeAmount,
    clock: Clock = .nio
  ) {
    self.eventLoop = eventLoop

    self.maxIdleTimer = maxIdleTime.map { Timer(delay: $0) }
    self.maxAgeTimer = maxAge.map { Timer(delay: $0) }
    self.maxGraceTimer = maxGraceTime.map { Timer(delay: $0) }

    self.keepAliveTimer = keepAliveTime.map { Timer(delay: $0) }
    // Always create a keep alive timeout timer, it's only used if there is a keep alive timer.
    self.keepAliveTimeoutTimer = Timer(delay: keepAliveTimeout ?? .seconds(20))

    // Generate a random value to be used as keep alive ping data.
    let pingData = UInt64.random(in: .min ... .max)
    self.keepAlivePingData = HTTP2PingData(withInteger: pingData)

    self.state = StateMachine(
      allowKeepAliveWithoutCalls: allowKeepAliveWithoutCalls,
      minPingReceiveIntervalWithoutCalls: minPingIntervalWithoutCalls,
      goAwayPingData: HTTP2PingData(withInteger: ~pingData)
    )

    self.flushPending = false
    self.inReadLoop = false
    self.clock = clock
    self.frameStats = FrameStats()
  }

  func handlerAdded(context: ChannelHandlerContext) {
    assert(context.eventLoop === self.eventLoop)
  }

  func channelActive(context: ChannelHandlerContext) {
    self.maxAgeTimer?.schedule(on: context.eventLoop) {
      self.initiateGracefulShutdown(context: context)
    }

    self.maxIdleTimer?.schedule(on: context.eventLoop) {
      self.initiateGracefulShutdown(context: context)
    }

    self.keepAliveTimer?.schedule(on: context.eventLoop) {
      self.keepAliveTimerFired(context: context)
    }

    context.fireChannelActive()
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.maxIdleTimer?.cancel()
    self.maxAgeTimer?.cancel()
    self.maxGraceTimer?.cancel()
    self.keepAliveTimer?.cancel()
    self.keepAliveTimeoutTimer.cancel()
    context.fireChannelInactive()
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch event {
    case let event as NIOHTTP2StreamCreatedEvent:
      // The connection isn't idle if a stream is open.
      self.maxIdleTimer?.cancel()
      self.state.streamOpened(event.streamID)

    case let event as StreamClosedEvent:
      switch self.state.streamClosed(event.streamID) {
      case .startIdleTimer:
        self.maxIdleTimer?.schedule(on: context.eventLoop) {
          self.initiateGracefulShutdown(context: context)
        }

      case .close:
        context.close(mode: .all, promise: nil)

      case .none:
        ()
      }

    default:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    self.inReadLoop = true

    // Any read data indicates that the connection is alive so cancel the keep-alive timers.
    self.keepAliveTimer?.cancel()
    self.keepAliveTimeoutTimer.cancel()

    let frame = self.unwrapInboundIn(data)
    switch frame.payload {
    case .ping(let data, let ack):
      if ack {
        self.handlePingAck(context: context, data: data)
      } else {
        self.handlePing(context: context, data: data)
      }

    default:
      ()  // Only interested in PING frames, ignore the rest.
    }

    context.fireChannelRead(data)
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    while self.flushPending {
      self.flushPending = false
      context.flush()
    }

    self.inReadLoop = false

    // Done reading: schedule the keep-alive timer.
    self.keepAliveTimer?.schedule(on: context.eventLoop) {
      self.keepAliveTimerFired(context: context)
    }

    context.fireChannelReadComplete()
  }

  func flush(context: ChannelHandlerContext) {
    self.maybeFlush(context: context)
  }
}

extension ServerConnectionManagementHandler {
  private func maybeFlush(context: ChannelHandlerContext) {
    if self.inReadLoop {
      self.flushPending = true
    } else {
      context.flush()
    }
  }

  private func initiateGracefulShutdown(context: ChannelHandlerContext) {
    context.eventLoop.assertInEventLoop()

    // Cancel any timers if initiating shutdown.
    self.maxIdleTimer?.cancel()
    self.maxAgeTimer?.cancel()
    self.keepAliveTimer?.cancel()
    self.keepAliveTimeoutTimer.cancel()

    switch self.state.startGracefulShutdown() {
    case .sendGoAwayAndPing(let pingData):
      // There's a time window between the server sending a GOAWAY frame and the client receiving
      // it. During this time the client may open new streams as it doesn't yet know about the
      // GOAWAY frame.
      //
      // The server therefore sends a GOAWAY with the last stream ID set to the maximum stream ID
      // and follows it with a PING frame. When the server receives the ack for the PING frame it
      // knows that the client has received the initial GOAWAY frame and that no more streams may
      // be opened. The server can then send an additional GOAWAY frame with a more representative
      // last stream ID.
      let goAway = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(
          lastStreamID: .maxID,
          errorCode: .noError,
          opaqueData: nil
        )
      )

      let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(pingData, ack: false))

      context.write(self.wrapOutboundOut(goAway), promise: nil)
      context.write(self.wrapOutboundOut(ping), promise: nil)
      self.maybeFlush(context: context)

    case .none:
      ()  // Already shutting down.
    }
  }

  private func handlePing(context: ChannelHandlerContext, data: HTTP2PingData) {
    switch self.state.receivedPing(atTime: self.clock.now(), data: data) {
    case .enhanceYourCalmThenClose(let streamID):
      let goAway = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(
          lastStreamID: streamID,
          errorCode: .enhanceYourCalm,
          opaqueData: context.channel.allocator.buffer(string: "too_many_pings")
        )
      )

      context.write(self.wrapOutboundOut(goAway), promise: nil)
      self.maybeFlush(context: context)
      context.close(promise: nil)

    case .sendAck:
      let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(data, ack: true))
      context.write(self.wrapOutboundOut(ping), promise: nil)
      self.maybeFlush(context: context)

    case .none:
      ()
    }
  }

  private func handlePingAck(context: ChannelHandlerContext, data: HTTP2PingData) {
    switch self.state.receivedPingAck(data: data) {
    case .sendGoAway(let streamID, let close):
      let goAway = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: streamID, errorCode: .noError, opaqueData: nil)
      )

      context.write(self.wrapOutboundOut(goAway), promise: nil)
      self.maybeFlush(context: context)

      if close {
        context.close(promise: nil)
      } else {
        // RPCs may have a grace period for finishing once the second GOAWAY frame has finished.
        // If this is set close the connection abruptly once the grace period passes.
        self.maxGraceTimer?.schedule(on: context.eventLoop) {
          context.close(promise: nil)
        }
      }

    case .none:
      ()
    }
  }

  private func keepAliveTimerFired(context: ChannelHandlerContext) {
    let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(self.keepAlivePingData, ack: false))
    context.write(self.wrapInboundOut(ping), promise: nil)
    self.maybeFlush(context: context)

    // Schedule a timeout on waiting for the response.
    self.keepAliveTimeoutTimer.schedule(on: context.eventLoop) {
      self.initiateGracefulShutdown(context: context)
    }
  }
}
