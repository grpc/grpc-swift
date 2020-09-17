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

  /// A logger.
  private let logger: Logger

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

  init(mode: Mode, logger: Logger, idleTimeout: TimeAmount) {
    self.mode = mode
    self.idleTimeout = idleTimeout
    self.logger = logger
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    switch self.state {
    case .notReady, .ready:
      if let created = event as? NIOHTTP2StreamCreatedEvent {
        // We have a stream: don't go idle
        self.scheduledIdle?.cancel()
        self.scheduledIdle = nil
        self.activeStreams += 1

        self.logger.debug("HTTP2 stream created", metadata: [
          MetadataKey.h2StreamID: "\(created.streamID)",
          MetadataKey.h2ActiveStreams: "\(self.activeStreams)",
        ])
      } else if let closed = event as? StreamClosedEvent {
        self.activeStreams -= 1

        self.logger.debug("HTTP2 stream closed", metadata: [
          MetadataKey.h2StreamID: "\(closed.streamID)",
          MetadataKey.h2ActiveStreams: "\(self.activeStreams)",
        ])

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
    self.scheduledIdle = nil
    self.state = .closed
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.scheduledIdle?.cancel()
    self.scheduledIdle = nil

    switch (self.mode, self.state) {
    case let (.client(manager), .notReady):
      self.state = .closed
      manager.channelInactive()

    case let (.client(manager), .ready):
      self.state = .closed

      if self.activeStreams == 0 {
        // We're ready and there are no active streams: we can treat this as the server idling our
        // connection.
        manager.idle()
      } else {
        manager.channelInactive()
      }

    case (.server, .notReady),
         (.server, .ready),
         (_, .closed):
      self.state = .closed
    }

    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)

    if frame.streamID == .rootStream {
      switch (self.state, frame.payload) {
      // We only care about SETTINGS as long as we are in state `.notReady`.
      case let (.notReady, .settings(content)):
        self.state = .ready

        switch self.mode {
        case let .client(manager):
          let remoteAddressDescription = context.channel.remoteAddress.map { "\($0)" } ?? "n/a"
          manager.logger.info("gRPC connection ready", metadata: [
            MetadataKey.remoteAddress: "\(remoteAddressDescription)",
            MetadataKey.eventLoop: "\(context.eventLoop)",
          ])

          // Let the manager know we're ready.
          manager.ready()

        case .server:
          ()
        }

        if case let .settings(settings) = content {
          self.logger.debug(
            "received initial HTTP2 settings",
            metadata: Dictionary(settings.map {
              ("\($0.parameter.loggingMetadataKey)", "\($0.value)")
            }, uniquingKeysWith: { a, _ in a })
          )
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
    guard self.activeStreams == 0, self.idleTimeout.nanoseconds != .max else {
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

      self.logger.debug("Closing idle channel")
      context.close(mode: .all, promise: nil)

    // We need to guard against double closure here. We may go idle as a result of receiving a
    // GOAWAY frame or because our scheduled idle timeout fired.
    case .closed:
      ()
    }
  }
}

extension HTTP2SettingsParameter {
  fileprivate var loggingMetadataKey: String {
    switch self {
    case .headerTableSize:
      return "h2_settings_header_table_size"
    case .enablePush:
      return "h2_settings_enable_push"
    case .maxConcurrentStreams:
      return "h2_settings_max_concurrent_streams"
    case .initialWindowSize:
      return "h2_settings_initial_window_size"
    case .maxFrameSize:
      return "h2_settings_max_frame_size"
    case .maxHeaderListSize:
      return "h2_settings_max_header_list_size"
    case .enableConnectProtocol:
      return "h2_settings_enable_connect_protocol"
    default:
      return String(describing: self)
    }
  }
}
