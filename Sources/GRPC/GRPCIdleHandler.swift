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

internal class GRPCIdleHandler: ChannelInboundHandler {
  typealias InboundIn = HTTP2Frame

  /// The amount of time to wait before closing the channel when there are no active streams.
  private let idleTimeout: TimeAmount

  /// The number of active streams.
  private var activeStreams = 0

  /// The scheduled task which will close the channel.
  private var scheduledIdle: Scheduled<Void>?

  /// Client and server have slightly different behaviours; track which we are following.
  private var mode: Mode

  /// The mode of operation: the client tracks additional connection state in the connection
  /// manager.
  internal enum Mode {
    case client(ConnectionManager)
    case server
  }

  /// The current connection state.
  private var state: State = .notReady

  private enum State {
    // We haven't marked the connection as "ready" yet.
    case notReady

    // The connection has been marked as "ready".
    case ready

    // We called `close` on the channel.
    case closed
  }

  init(mode: Mode, idleTimeout: TimeAmount = .minutes(5)) {
    self.mode = mode
    self.idleTimeout = idleTimeout
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch self.state {
    case .notReady, .ready:
      if event is NIOHTTP2StreamCreatedEvent {
        // We have a stream: don't go idle
        self.scheduledIdle?.cancel()
        self.scheduledIdle = nil

        self.activeStreams += 1
      } else if event is StreamClosedEvent {
        self.activeStreams -= 1
        // No active streams: go idle soon.
        if self.activeStreams == 0 {
          self.scheduleIdleTimeout(context: context)
        }
      } else if event is ConnectionIdledEvent {
        // Force idle (closing) because we received a `ConnectionIdledEvent` from a keepalive handler
        self.idle(context: context, force: true)
      }

    case .closed:
      ()
    }

    context.fireUserInboundEventTriggered(event)
  }

  func channelActive(context: ChannelHandlerContext) {
    switch (self.mode, self.state) {
    // The client should become active: we'll only schedule the idling when the channel
    // becomes 'ready'.
    case let (.client(manager), .notReady):
      manager.channelActive(channel: context.channel)

    case (.server, .notReady),
         (_, .ready),
         (_, .closed):
      ()
    }

    context.fireChannelActive()
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.scheduledIdle?.cancel()
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.scheduledIdle?.cancel()
    self.scheduledIdle = nil

    switch (self.mode, self.state) {
    case let (.client(manager), .notReady),
         let (.client(manager), .ready):
      manager.channelInactive()

    case (.server, .notReady),
         (.server, .ready),
         (_, .closed):
      ()
    }

    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)

    if frame.streamID == .rootStream {
      switch (self.state, frame.payload) {
      // We only care about SETTINGS as long as we are in state `.notReady`.
      case (.notReady, .settings):
        self.state = .ready

        switch self.mode {
        case let .client(manager):
          let remoteAddressDescription = context.channel.remoteAddress.map { "\($0)" } ?? "n/a"
          manager.logger.info("gRPC connection ready", metadata: [
            "remote_address": "\(remoteAddressDescription)",
            "event_loop": "\(context.eventLoop)",
          ])

          // Let the manager know we're ready.
          manager.ready()

        case .server:
          ()
        }

        // Start the idle timeout.
        self.scheduleIdleTimeout(context: context)

      case (.notReady, .goAway),
           (.ready, .goAway):
        self.idle(context: context)

      default:
        ()
      }
    }

    context.fireChannelRead(data)
  }

  private func scheduleIdleTimeout(context: ChannelHandlerContext) {
    guard self.activeStreams == 0 else {
      return
    }

    self.scheduledIdle = context.eventLoop.scheduleTask(in: self.idleTimeout) {
      self.idle(context: context)
    }
  }

  private func idle(context: ChannelHandlerContext, force: Bool = false) {
    // Don't idle if there are active streams unless we manually request
    // example: keepalive handler sends a `ConnectionIdledEvent` event
    guard self.activeStreams == 0 || force else {
      return
    }

    switch self.state {
    case .notReady, .ready:
      self.state = .closed
      switch self.mode {
      case let .client(manager):
        manager.idle()
      case .server:
        ()
      }
      context.close(mode: .all, promise: nil)

    // We need to guard against double closure here. We may go idle as a result of receiving a
    // GOAWAY frame or because our scheduled idle timeout fired.
    case .closed:
      ()
    }
  }
}
