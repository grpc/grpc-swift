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

/// An event which happens on a client's HTTP/2 connection.
enum ClientConnectionEvent: Sendable, Hashable {
  enum CloseReason: Sendable, Hashable {
    /// The server sent a GOAWAY frame to the client.
    case goAway(HTTP2ErrorCode, String)
    /// The keep alive timer fired and subsequently timed out.
    case keepAliveExpired
    /// The connection became idle.
    case idle
  }

  /// The connection has started shutting down, no new streams should be created.
  case closing(CloseReason)
}

/// A `ChannelHandler` which manages part of the lifecycle of a gRPC connection over HTTP/2.
///
/// This handler is responsible for managing several aspects of the connection. These include:
/// 1. Periodically sending keep alive pings to the server (if configured) and closing the
///    connection if necessary.
/// 2. Closing the connection if it is idle (has no open streams) for a configured amount of time.
/// 3. Forwarding lifecycle events to the next handler.
///
/// Some of the behaviours are described in [gRFC A8](https://github.com/grpc/proposal/blob/master/A8-client-side-keepalive.md).
final class ClientConnectionHandler: ChannelInboundHandler, ChannelOutboundHandler {
  typealias InboundIn = HTTP2Frame
  typealias InboundOut = ClientConnectionEvent

  typealias OutboundIn = Never
  typealias OutboundOut = HTTP2Frame

  /// The `EventLoop` of the `Channel` this handler exists in.
  private let eventLoop: EventLoop

  /// The maximum amount of time the connection may be idle for. If the connection remains idle
  /// (i.e. has no open streams) for this period of time then the connection will be gracefully
  /// closed.
  private var maxIdleTimer: Timer?

  /// The amount of time to wait before sending a keep alive ping.
  private var keepAliveTimer: Timer?

  /// The amount of time the client has to reply after sending a keep alive ping. Only used if
  /// `keepAliveTimer` is set.
  private var keepAliveTimeoutTimer: Timer

  /// Opaque data sent in keep alive pings.
  private let keepAlivePingData: HTTP2PingData

  /// The current state of the connection.
  private var state: StateMachine

  /// Whether a flush is pending.
  private var flushPending: Bool
  /// Whether `channelRead` has been called and `channelReadComplete` hasn't yet been called.
  /// Resets once `channelReadComplete` returns.
  private var inReadLoop: Bool

  /// Creates a new handler which manages the lifecycle of a connection.
  ///
  /// - Parameters:
  ///   - eventLoop: The `EventLoop` of the `Channel` this handler is placed in.
  ///   - maxIdleTime: The maximum amount time a connection may be idle for before being closed.
  ///   - keepAliveTime: The amount of time to wait after reading data before sending a keep-alive
  ///       ping.
  ///   - keepAliveTimeout: The amount of time the client has to reply after the server sends a
  ///       keep-alive ping to keep the connection open. The connection is closed if no reply
  ///       is received.
  ///   - keepAliveWithoutCalls: Whether the client sends keep-alive pings when there are no calls
  ///       in progress.
  init(
    eventLoop: EventLoop,
    maxIdleTime: TimeAmount?,
    keepAliveTime: TimeAmount?,
    keepAliveTimeout: TimeAmount?,
    keepAliveWithoutCalls: Bool
  ) {
    self.eventLoop = eventLoop
    self.maxIdleTimer = maxIdleTime.map { Timer(delay: $0) }
    self.keepAliveTimer = keepAliveTime.map { Timer(delay: $0, repeat: true) }
    self.keepAliveTimeoutTimer = Timer(delay: keepAliveTimeout ?? .seconds(20))
    self.keepAlivePingData = HTTP2PingData(withInteger: .random(in: .min ... .max))
    self.state = StateMachine(allowKeepAliveWithoutCalls: keepAliveWithoutCalls)

    self.flushPending = false
    self.inReadLoop = false
  }

  func handlerAdded(context: ChannelHandlerContext) {
    assert(context.eventLoop === self.eventLoop)
  }

  func channelActive(context: ChannelHandlerContext) {
    self.keepAliveTimer?.schedule(on: context.eventLoop) {
      self.keepAliveTimerFired(context: context)
    }

    self.maxIdleTimer?.schedule(on: context.eventLoop) {
      self.maxIdleTimerFired(context: context)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.state.closed()
    self.keepAliveTimer?.cancel()
    self.keepAliveTimeoutTimer.cancel()
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch event {
    case let event as NIOHTTP2StreamCreatedEvent:
      // Stream created, so the connection isn't idle.
      self.maxIdleTimer?.cancel()
      self.state.streamOpened(event.streamID)

    case let event as StreamClosedEvent:
      switch self.state.streamClosed(event.streamID) {
      case .startIdleTimer(let cancelKeepAlive):
        // All streams are closed, restart the idle timer, and stop the keep-alive timer (it may
        // not stop if keep-alive is allowed when there are no active calls).
        self.maxIdleTimer?.schedule(on: context.eventLoop) {
          self.maxIdleTimerFired(context: context)
        }

        if cancelKeepAlive {
          self.keepAliveTimer?.cancel()
        }

      case .close:
        // Connection was closing but waiting for all streams to close. They must all be closed
        // now so close the connection.
        context.close(promise: nil)

      case .none:
        ()
      }

    default:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)
    self.inReadLoop = true

    switch frame.payload {
    case .goAway(_, let errorCode, let data):
      // Receiving a GOAWAY frame means we need to stop creating streams immediately and start
      // closing the connection.
      switch self.state.beginGracefulShutdown() {
      case .sendGoAway(let close):
        // gRPC servers may indicate why the GOAWAY was sent in the opaque data.
        let message = data.map { String(buffer: $0) } ?? ""
        context.fireChannelRead(self.wrapInboundOut(.closing(.goAway(errorCode, message))))

        // Clients should send GOAWAYs when closing a connection.
        self.writeAndFlushGoAway(context: context, errorCode: .noError)
        if close {
          context.close(promise: nil)
        }

      case .none:
        ()
      }

    case .ping(let data, let ack):
      // Pings are ack'd by the HTTP/2 handler so we only pay attention to acks here, and in
      // particular only those carrying the keep-alive data.
      if ack, data == self.keepAlivePingData {
        self.keepAliveTimeoutTimer.cancel()
        self.keepAliveTimer?.schedule(on: context.eventLoop) {
          self.keepAliveTimerFired(context: context)
        }
      }

    default:
      ()
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    while self.flushPending {
      self.flushPending = false
      context.flush()
    }

    self.inReadLoop = false
    context.fireChannelReadComplete()
  }
}

extension ClientConnectionHandler {
  private func maybeFlush(context: ChannelHandlerContext) {
    if self.inReadLoop {
      self.flushPending = true
    } else {
      context.flush()
    }
  }

  private func keepAliveTimerFired(context: ChannelHandlerContext) {
    guard self.state.sendKeepAlivePing() else { return }

    // Cancel the keep alive timer when the client sends a ping. The timer is resumed when the ping
    // is acknowledged.
    self.keepAliveTimer?.cancel()

    let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(self.keepAlivePingData, ack: false))
    context.write(self.wrapOutboundOut(ping), promise: nil)
    self.maybeFlush(context: context)

    // Schedule a timeout on waiting for the response.
    self.keepAliveTimeoutTimer.schedule(on: context.eventLoop) {
      self.keepAliveTimeoutExpired(context: context)
    }
  }

  private func keepAliveTimeoutExpired(context: ChannelHandlerContext) {
    guard self.state.beginClosing() else { return }

    context.fireChannelRead(self.wrapInboundOut(.closing(.keepAliveExpired)))
    self.writeAndFlushGoAway(context: context, message: "keepalive_expired")
    context.close(promise: nil)
  }

  private func maxIdleTimerFired(context: ChannelHandlerContext) {
    guard self.state.beginClosing() else { return }

    context.fireChannelRead(self.wrapInboundOut(.closing(.idle)))
    self.writeAndFlushGoAway(context: context, message: "idle")
    context.close(promise: nil)
  }

  private func writeAndFlushGoAway(
    context: ChannelHandlerContext,
    errorCode: HTTP2ErrorCode = .noError,
    message: String? = nil
  ) {
    let goAway = HTTP2Frame(
      streamID: .rootStream,
      payload: .goAway(
        lastStreamID: 0,
        errorCode: errorCode,
        opaqueData: message.map { context.channel.allocator.buffer(string: $0) }
      )
    )

    context.write(self.wrapOutboundOut(goAway), promise: nil)
    self.maybeFlush(context: context)
  }
}

extension ClientConnectionHandler {
  struct StateMachine {
    private var state: State

    private enum State {
      case active(Active)
      case closing(Closing)
      case closed

      struct Active {
        var openStreams: Set<HTTP2StreamID>
        var allowKeepAliveWithoutCalls: Bool

        init(allowKeepAliveWithoutCalls: Bool) {
          self.openStreams = []
          self.allowKeepAliveWithoutCalls = allowKeepAliveWithoutCalls
        }
      }

      struct Closing {
        var allowKeepAliveWithoutCalls: Bool
        var openStreams: Set<HTTP2StreamID>

        init(from state: Active) {
          self.openStreams = state.openStreams
          self.allowKeepAliveWithoutCalls = state.allowKeepAliveWithoutCalls
        }
      }
    }

    init(allowKeepAliveWithoutCalls: Bool) {
      self.state = .active(State.Active(allowKeepAliveWithoutCalls: allowKeepAliveWithoutCalls))
    }

    /// Record that the stream with the given ID has been opened.
    mutating func streamOpened(_ id: HTTP2StreamID) {
      switch self.state {
      case .active(var state):
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .active(state)

      case .closing(var state):
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .closing(state)

      case .closed:
        ()
      }
    }

    enum OnStreamClosed: Equatable {
      /// Start the idle timer, after which the connection should be closed gracefully.
      case startIdleTimer(cancelKeepAlive: Bool)
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
        if state.openStreams.isEmpty {
          onStreamClosed = .startIdleTimer(cancelKeepAlive: !state.allowKeepAliveWithoutCalls)
        } else {
          onStreamClosed = .none
        }
        self.state = .active(state)

      case .closing(var state):
        let removedID = state.openStreams.remove(id)
        assert(removedID != nil, "Can't close stream \(Int(id)), it wasn't open")
        onStreamClosed = state.openStreams.isEmpty ? .close : .none
        self.state = .closing(state)

      case .closed:
        onStreamClosed = .none
      }

      return onStreamClosed
    }

    /// Returns whether a keep alive ping should be sent to the server.
    mutating func sendKeepAlivePing() -> Bool {
      let sendKeepAlivePing: Bool

      // Only send a ping if there are open streams or there are no open streams and keep alive
      // is permitted when there are no active calls.
      switch self.state {
      case .active(let state):
        sendKeepAlivePing = !state.openStreams.isEmpty || state.allowKeepAliveWithoutCalls
      case .closing(let state):
        sendKeepAlivePing = !state.openStreams.isEmpty || state.allowKeepAliveWithoutCalls
      case .closed:
        sendKeepAlivePing = false
      }

      return sendKeepAlivePing
    }

    enum OnGracefulShutDown: Equatable {
      case sendGoAway(Bool)
      case none
    }

    mutating func beginGracefulShutdown() -> OnGracefulShutDown {
      let onGracefulShutdown: OnGracefulShutDown

      switch self.state {
      case .active(let state):
        // Only close immediately if there are no open streams. The client doesn't need to
        // ratchet down the last stream ID as only the client creates streams in gRPC.
        let close = state.openStreams.isEmpty
        onGracefulShutdown = .sendGoAway(close)
        self.state = .closing(State.Closing(from: state))

      case .closing, .closed:
        onGracefulShutdown = .none
      }

      return onGracefulShutdown
    }

    /// Returns whether the connection should be closed.
    mutating func beginClosing() -> Bool {
      switch self.state {
      case .active(let active):
        self.state = .closing(State.Closing(from: active))
        return true
      case .closing, .closed:
        return false
      }
    }

    /// Marks the state as closed.
    mutating func closed() {
      self.state = .closed
    }
  }
}
