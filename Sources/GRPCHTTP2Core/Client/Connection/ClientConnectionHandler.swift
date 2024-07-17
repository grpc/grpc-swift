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
package enum ClientConnectionEvent: Sendable {
  package enum CloseReason: Sendable {
    /// The server sent a GOAWAY frame to the client.
    case goAway(HTTP2ErrorCode, String)
    /// The keep alive timer fired and subsequently timed out.
    case keepaliveExpired
    /// The connection became idle.
    case idle
    /// The local peer initiated the close.
    case initiatedLocally
    /// The connection was closed unexpectedly
    case unexpected((any Error)?, isIdle: Bool)
  }

  /// The connection is now ready.
  case ready

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
package final class ClientConnectionHandler: ChannelInboundHandler, ChannelOutboundHandler {
  package typealias InboundIn = HTTP2Frame
  package typealias InboundOut = ClientConnectionEvent

  package typealias OutboundIn = Never
  package typealias OutboundOut = HTTP2Frame

  package enum OutboundEvent: Hashable, Sendable {
    /// Close the connection gracefully
    case closeGracefully
  }

  /// The `EventLoop` of the `Channel` this handler exists in.
  private let eventLoop: any EventLoop

  /// The maximum amount of time the connection may be idle for. If the connection remains idle
  /// (i.e. has no open streams) for this period of time then the connection will be gracefully
  /// closed.
  private var maxIdleTimer: Timer?

  /// The amount of time to wait before sending a keep alive ping.
  private var keepaliveTimer: Timer?

  /// The amount of time the client has to reply after sending a keep alive ping. Only used if
  /// `keepaliveTimer` is set.
  private var keepaliveTimeoutTimer: Timer

  /// Opaque data sent in keep alive pings.
  private let keepalivePingData: HTTP2PingData

  /// The current state of the connection.
  private var state: StateMachine

  /// Whether a flush is pending.
  private var flushPending: Bool
  /// Whether `channelRead` has been called and `channelReadComplete` hasn't yet been called.
  /// Resets once `channelReadComplete` returns.
  private var inReadLoop: Bool

  /// The context of the channel this handler is in.
  private var context: ChannelHandlerContext?

  /// Creates a new handler which manages the lifecycle of a connection.
  ///
  /// - Parameters:
  ///   - eventLoop: The `EventLoop` of the `Channel` this handler is placed in.
  ///   - maxIdleTime: The maximum amount time a connection may be idle for before being closed.
  ///   - keepaliveTime: The amount of time to wait after reading data before sending a keep-alive
  ///       ping.
  ///   - keepaliveTimeout: The amount of time the client has to reply after the server sends a
  ///       keep-alive ping to keep the connection open. The connection is closed if no reply
  ///       is received.
  ///   - keepaliveWithoutCalls: Whether the client sends keep-alive pings when there are no calls
  ///       in progress.
  package init(
    eventLoop: any EventLoop,
    maxIdleTime: TimeAmount?,
    keepaliveTime: TimeAmount?,
    keepaliveTimeout: TimeAmount?,
    keepaliveWithoutCalls: Bool
  ) {
    self.eventLoop = eventLoop
    self.maxIdleTimer = maxIdleTime.map { Timer(delay: $0) }
    self.keepaliveTimer = keepaliveTime.map { Timer(delay: $0, repeat: true) }
    self.keepaliveTimeoutTimer = Timer(delay: keepaliveTimeout ?? .seconds(20))
    self.keepalivePingData = HTTP2PingData(withInteger: .random(in: .min ... .max))
    self.state = StateMachine(allowKeepaliveWithoutCalls: keepaliveWithoutCalls)

    self.flushPending = false
    self.inReadLoop = false
  }

  package func handlerAdded(context: ChannelHandlerContext) {
    assert(context.eventLoop === self.eventLoop)
    self.context = context
  }

  package func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
  }

  package func channelInactive(context: ChannelHandlerContext) {
    switch self.state.closed() {
    case .none:
      ()

    case .unexpectedClose(let error, let isIdle):
      let event = self.wrapInboundOut(.closing(.unexpected(error, isIdle: isIdle)))
      context.fireChannelRead(event)

    case .succeed(let promise):
      promise.succeed()
    }

    self.keepaliveTimer?.cancel()
    self.keepaliveTimeoutTimer.cancel()
  }

  package func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch event {
    case let event as NIOHTTP2StreamCreatedEvent:
      self._streamCreated(event.streamID, channel: context.channel)

    case let event as StreamClosedEvent:
      self._streamClosed(event.streamID, channel: context.channel)

    default:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  package func errorCaught(context: ChannelHandlerContext, error: any Error) {
    // Store the error and close, this will result in the final close event being fired down
    // the pipeline with an appropriate close reason and appropriate error. (This avoids
    // the async channel just throwing the error.)
    self.state.receivedError(error)
    context.close(mode: .all, promise: nil)
  }

  package func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)
    self.inReadLoop = true

    switch frame.payload {
    case .goAway(_, let errorCode, let data):
      // Receiving a GOAWAY frame means we need to stop creating streams immediately and start
      // closing the connection.
      switch self.state.beginGracefulShutdown(promise: nil) {
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
      if ack, data == self.keepalivePingData {
        let loopBound = LoopBoundView(handler: self, context: context)
        self.keepaliveTimeoutTimer.cancel()
        self.keepaliveTimer?.schedule(on: context.eventLoop) {
          loopBound.keepaliveTimerFired()
        }
      }

    case .settings(.settings(_)):
      let isInitialSettings = self.state.receivedSettings()

      // The first settings frame indicates that the connection is now ready to use. The channel
      // becoming active is insufficient as, for example, a TLS handshake may fail after
      // establishing the TCP connection, or the server isn't configured for gRPC (or HTTP/2).
      if isInitialSettings {
        let loopBound = LoopBoundView(handler: self, context: context)
        self.keepaliveTimer?.schedule(on: context.eventLoop) {
          loopBound.keepaliveTimerFired()
        }

        self.maxIdleTimer?.schedule(on: context.eventLoop) {
          loopBound.maxIdleTimerFired()
        }

        context.fireChannelRead(self.wrapInboundOut(.ready))
      }

    default:
      ()
    }
  }

  package func channelReadComplete(context: ChannelHandlerContext) {
    while self.flushPending {
      self.flushPending = false
      context.flush()
    }

    self.inReadLoop = false
    context.fireChannelReadComplete()
  }

  package func triggerUserOutboundEvent(
    context: ChannelHandlerContext,
    event: Any,
    promise: EventLoopPromise<Void>?
  ) {
    if let event = event as? OutboundEvent {
      switch event {
      case .closeGracefully:
        switch self.state.beginGracefulShutdown(promise: promise) {
        case .sendGoAway(let close):
          context.fireChannelRead(self.wrapInboundOut(.closing(.initiatedLocally)))
          // The client could send a GOAWAY at this point but it's not really necessary, the server
          // can't open streams anyway, the client will just close the connection when it's done.
          if close {
            context.close(promise: nil)
          }

        case .none:
          ()
        }
      }
    } else {
      context.triggerUserOutboundEvent(event, promise: promise)
    }
  }
}

extension ClientConnectionHandler {
  struct LoopBoundView: @unchecked Sendable {
    private let handler: ClientConnectionHandler
    private let context: ChannelHandlerContext

    init(handler: ClientConnectionHandler, context: ChannelHandlerContext) {
      self.handler = handler
      self.context = context
    }

    func keepaliveTimerFired() {
      self.context.eventLoop.assertInEventLoop()
      self.handler.keepaliveTimerFired(context: self.context)
    }

    func keepaliveTimeoutExpired() {
      self.context.eventLoop.assertInEventLoop()
      self.handler.keepaliveTimeoutExpired(context: self.context)
    }

    func maxIdleTimerFired() {
      self.context.eventLoop.assertInEventLoop()
      self.handler.maxIdleTimerFired(context: self.context)
    }
  }
}

extension ClientConnectionHandler {
  package struct HTTP2StreamDelegate: @unchecked Sendable, NIOHTTP2StreamDelegate {
    // @unchecked is okay: the only methods do the appropriate event-loop dance.

    private let handler: ClientConnectionHandler

    init(_ handler: ClientConnectionHandler) {
      self.handler = handler
    }

    package func streamCreated(_ id: HTTP2StreamID, channel: any Channel) {
      if self.handler.eventLoop.inEventLoop {
        self.handler._streamCreated(id, channel: channel)
      } else {
        self.handler.eventLoop.execute {
          self.handler._streamCreated(id, channel: channel)
        }
      }
    }

    package func streamClosed(_ id: HTTP2StreamID, channel: any Channel) {
      if self.handler.eventLoop.inEventLoop {
        self.handler._streamClosed(id, channel: channel)
      } else {
        self.handler.eventLoop.execute {
          self.handler._streamClosed(id, channel: channel)
        }
      }
    }
  }

  package var http2StreamDelegate: HTTP2StreamDelegate {
    return HTTP2StreamDelegate(self)
  }

  private func _streamCreated(_ id: HTTP2StreamID, channel: any Channel) {
    self.eventLoop.assertInEventLoop()

    // Stream created, so the connection isn't idle.
    self.maxIdleTimer?.cancel()
    self.state.streamOpened(id)
  }

  private func _streamClosed(_ id: HTTP2StreamID, channel: any Channel) {
    guard let context = self.context else { return }
    self.eventLoop.assertInEventLoop()

    switch self.state.streamClosed(id) {
    case .startIdleTimer(let cancelKeepalive):
      // All streams are closed, restart the idle timer, and stop the keep-alive timer (it may
      // not stop if keep-alive is allowed when there are no active calls).
      let loopBound = LoopBoundView(handler: self, context: context)
      self.maxIdleTimer?.schedule(on: context.eventLoop) {
        loopBound.maxIdleTimerFired()
      }

      if cancelKeepalive {
        self.keepaliveTimer?.cancel()
      }

    case .close:
      // Connection was closing but waiting for all streams to close. They must all be closed
      // now so close the connection.
      context.close(promise: nil)

    case .none:
      ()
    }
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

  private func keepaliveTimerFired(context: ChannelHandlerContext) {
    guard self.state.sendKeepalivePing() else { return }

    // Cancel the keep alive timer when the client sends a ping. The timer is resumed when the ping
    // is acknowledged.
    self.keepaliveTimer?.cancel()

    let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(self.keepalivePingData, ack: false))
    context.write(self.wrapOutboundOut(ping), promise: nil)
    self.maybeFlush(context: context)

    // Schedule a timeout on waiting for the response.
    let loopBound = LoopBoundView(handler: self, context: context)
    self.keepaliveTimeoutTimer.schedule(on: context.eventLoop) {
      loopBound.keepaliveTimeoutExpired()
    }
  }

  private func keepaliveTimeoutExpired(context: ChannelHandlerContext) {
    guard self.state.beginClosing() else { return }

    context.fireChannelRead(self.wrapInboundOut(.closing(.keepaliveExpired)))
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
      case _modifying

      struct Active {
        var openStreams: Set<HTTP2StreamID>
        var allowKeepaliveWithoutCalls: Bool
        var receivedConnectionPreface: Bool
        var error: (any Error)?

        init(allowKeepaliveWithoutCalls: Bool) {
          self.openStreams = []
          self.allowKeepaliveWithoutCalls = allowKeepaliveWithoutCalls
          self.receivedConnectionPreface = false
          self.error = nil
        }

        mutating func receivedSettings() -> Bool {
          let isFirstSettingsFrame = !self.receivedConnectionPreface
          self.receivedConnectionPreface = true
          return isFirstSettingsFrame
        }
      }

      struct Closing {
        var allowKeepaliveWithoutCalls: Bool
        var openStreams: Set<HTTP2StreamID>
        var closePromise: Optional<EventLoopPromise<Void>>

        init(from state: Active, closePromise: EventLoopPromise<Void>?) {
          self.openStreams = state.openStreams
          self.allowKeepaliveWithoutCalls = state.allowKeepaliveWithoutCalls
          self.closePromise = closePromise
        }
      }
    }

    init(allowKeepaliveWithoutCalls: Bool) {
      self.state = .active(State.Active(allowKeepaliveWithoutCalls: allowKeepaliveWithoutCalls))
    }

    /// Record that a SETTINGS frame was received from the remote peer.
    ///
    /// - Returns: `true` if this was the first SETTINGS frame received.
    mutating func receivedSettings() -> Bool {
      switch self.state {
      case .active(var active):
        self.state = ._modifying
        let isFirstSettingsFrame = active.receivedSettings()
        self.state = .active(active)
        return isFirstSettingsFrame

      case .closing, .closed:
        return false

      case ._modifying:
        preconditionFailure()
      }
    }

    /// Record that an error was received.
    mutating func receivedError(_ error: any Error) {
      switch self.state {
      case .active(var active):
        self.state = ._modifying
        active.error = error
        self.state = .active(active)
      case .closing, .closed:
        ()
      case ._modifying:
        preconditionFailure()
      }
    }

    /// Record that the stream with the given ID has been opened.
    mutating func streamOpened(_ id: HTTP2StreamID) {
      switch self.state {
      case .active(var state):
        self.state = ._modifying
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .active(state)

      case .closing(var state):
        self.state = ._modifying
        let (inserted, _) = state.openStreams.insert(id)
        assert(inserted, "Can't open stream \(Int(id)), it's already open")
        self.state = .closing(state)

      case .closed:
        ()

      case ._modifying:
        preconditionFailure()
      }
    }

    enum OnStreamClosed: Equatable {
      /// Start the idle timer, after which the connection should be closed gracefully.
      case startIdleTimer(cancelKeepalive: Bool)
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
        self.state = ._modifying
        let removedID = state.openStreams.remove(id)
        assert(removedID != nil, "Can't close stream \(Int(id)), it wasn't open")
        if state.openStreams.isEmpty {
          onStreamClosed = .startIdleTimer(cancelKeepalive: !state.allowKeepaliveWithoutCalls)
        } else {
          onStreamClosed = .none
        }
        self.state = .active(state)

      case .closing(var state):
        self.state = ._modifying
        let removedID = state.openStreams.remove(id)
        assert(removedID != nil, "Can't close stream \(Int(id)), it wasn't open")
        onStreamClosed = state.openStreams.isEmpty ? .close : .none
        self.state = .closing(state)

      case .closed:
        onStreamClosed = .none

      case ._modifying:
        preconditionFailure()
      }

      return onStreamClosed
    }

    /// Returns whether a keep alive ping should be sent to the server.
    func sendKeepalivePing() -> Bool {
      let sendKeepalivePing: Bool

      // Only send a ping if there are open streams or there are no open streams and keep alive
      // is permitted when there are no active calls.
      switch self.state {
      case .active(let state):
        sendKeepalivePing = !state.openStreams.isEmpty || state.allowKeepaliveWithoutCalls
      case .closing(let state):
        sendKeepalivePing = !state.openStreams.isEmpty || state.allowKeepaliveWithoutCalls
      case .closed:
        sendKeepalivePing = false
      case ._modifying:
        preconditionFailure()
      }

      return sendKeepalivePing
    }

    enum OnGracefulShutDown: Equatable {
      case sendGoAway(Bool)
      case none
    }

    mutating func beginGracefulShutdown(promise: EventLoopPromise<Void>?) -> OnGracefulShutDown {
      let onGracefulShutdown: OnGracefulShutDown

      switch self.state {
      case .active(let state):
        self.state = ._modifying
        // Only close immediately if there are no open streams. The client doesn't need to
        // ratchet down the last stream ID as only the client creates streams in gRPC.
        let close = state.openStreams.isEmpty
        onGracefulShutdown = .sendGoAway(close)
        self.state = .closing(State.Closing(from: state, closePromise: promise))

      case .closing(var state):
        self.state = ._modifying
        state.closePromise.setOrCascade(to: promise)
        self.state = .closing(state)
        onGracefulShutdown = .none

      case .closed:
        onGracefulShutdown = .none

      case ._modifying:
        preconditionFailure()
      }

      return onGracefulShutdown
    }

    /// Returns whether the connection should be closed.
    mutating func beginClosing() -> Bool {
      switch self.state {
      case .active(let active):
        self.state = .closing(State.Closing(from: active, closePromise: nil))
        return true
      case .closing, .closed:
        return false
      case ._modifying:
        preconditionFailure()
      }
    }

    enum OnClosed {
      case succeed(EventLoopPromise<Void>)
      case unexpectedClose((any Error)?, isIdle: Bool)
      case none
    }

    /// Marks the state as closed.
    mutating func closed() -> OnClosed {
      switch self.state {
      case .active(let state):
        self.state = .closed
        return .unexpectedClose(state.error, isIdle: state.openStreams.isEmpty)
      case .closing(let closing):
        self.state = .closed
        return closing.closePromise.map { .succeed($0) } ?? .none
      case .closed:
        self.state = .closed
        return .none
      case ._modifying:
        preconditionFailure()
      }
    }
  }
}
