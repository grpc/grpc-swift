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
import NIOTLS
import NIOTransportServices

internal final class GRPCIdleHandler: ChannelInboundHandler {
  typealias InboundIn = HTTP2Frame
  typealias OutboundOut = HTTP2Frame

  /// The amount of time to wait before closing the channel when there are no active streams.
  /// If nil, then we shouldn't schedule idle tasks.
  private let idleTimeout: TimeAmount?

  /// The ping handler.
  private var pingHandler: PingHandler

  /// The scheduled task which will close the connection after the keep-alive timeout has expired.
  private var scheduledClose: Scheduled<Void>?

  /// The scheduled task which will ping.
  private var scheduledPing: RepeatedTask?

  /// The mode we're operating in.
  private let mode: Mode

  /// The time the handler was created.
  private let creationTime: NIODeadline

  /// Returns the age of the connection in seconds.
  private var connectionAgeInSeconds: UInt64 {
    let now = NIODeadline.now()
    let nanoseconds = now.uptimeNanoseconds - self.creationTime.uptimeNanoseconds
    let seconds = nanoseconds / 1_000_000_000
    return seconds
  }

  private var context: ChannelHandlerContext?

  /// The mode of operation: the client tracks additional connection state in the connection
  /// manager.
  internal enum Mode {
    case client(ConnectionManager, HTTP2StreamMultiplexer)
    case server

    var connectionManager: ConnectionManager? {
      switch self {
      case let .client(manager, _):
        return manager
      case .server:
        return nil
      }
    }
  }

  /// The current state.
  private var stateMachine: GRPCIdleHandlerStateMachine

  init(
    connectionManager: ConnectionManager,
    multiplexer: HTTP2StreamMultiplexer,
    idleTimeout: TimeAmount,
    keepalive configuration: ClientConnectionKeepalive,
    logger: Logger
  ) {
    self.mode = .client(connectionManager, multiplexer)
    switch connectionManager.idleBehavior {
    case .neverGoIdle:
      self.idleTimeout = nil
    case .closeWhenIdleTimeout:
      self.idleTimeout = idleTimeout
    }
    self.stateMachine = .init(role: .client, logger: logger)
    self.pingHandler = PingHandler(
      pingCode: 5,
      interval: configuration.interval,
      timeout: configuration.timeout,
      permitWithoutCalls: configuration.permitWithoutCalls,
      maximumPingsWithoutData: configuration.maximumPingsWithoutData,
      minimumSentPingIntervalWithoutData: configuration.minimumSentPingIntervalWithoutData
    )
    self.creationTime = .now()
  }

  init(
    idleTimeout: TimeAmount,
    keepalive configuration: ServerConnectionKeepalive,
    logger: Logger
  ) {
    self.mode = .server
    self.stateMachine = .init(role: .server, logger: logger)
    self.idleTimeout = idleTimeout
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
    self.creationTime = .now()
  }

  private func perform(operations: GRPCIdleHandlerStateMachine.Operations) {
    // Prod the connection manager.
    if let event = operations.connectionManagerEvent, let manager = self.mode.connectionManager {
      switch event {
      case .idle:
        manager.idle()
      case .inactive:
        manager.channelInactive()
      case .ready:
        manager.ready()
      case .quiescing:
        manager.beginQuiescing()
      }
    }

    // Max concurrent streams changed.
    if let manager = self.mode.connectionManager,
      let maxConcurrentStreams = operations.maxConcurrentStreamsChange
    {
      manager.maxConcurrentStreamsChanged(maxConcurrentStreams)
    }

    // Handle idle timeout creation/cancellation.
    if let idleTimeout = self.idleTimeout, let idleTask = operations.idleTask {
      switch idleTask {
      case let .cancel(task):
        self.stateMachine.logger.debug("idle timeout task cancelled")
        task.cancel()

      case .schedule:
        if self.idleTimeout != .nanoseconds(.max), let context = self.context {
          self.stateMachine.logger.debug(
            "scheduling idle timeout task",
            metadata: [MetadataKey.delayMs: "\(idleTimeout.milliseconds)"]
          )
          let task = context.eventLoop.scheduleTask(in: idleTimeout) {
            self.stateMachine.logger.debug("idle timeout task fired")
            self.idleTimeoutFired()
          }
          self.perform(operations: self.stateMachine.scheduledIdleTimeoutTask(task))
        }
      }
    }

    // Send a GOAWAY frame.
    if let streamID = operations.sendGoAwayWithLastPeerInitiatedStreamID {
      self.stateMachine.logger.debug(
        "sending GOAWAY frame",
        metadata: [
          MetadataKey.h2GoAwayLastStreamID: "\(Int(streamID))"
        ]
      )

      let goAwayFrame = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: streamID, errorCode: .noError, opaqueData: nil)
      )

      self.context?.write(self.wrapOutboundOut(goAwayFrame), promise: nil)

      // We emit a ping after some GOAWAY frames.
      if operations.shouldPingAfterGoAway {
        let pingFrame = HTTP2Frame(
          streamID: .rootStream,
          payload: .ping(self.pingHandler.pingDataGoAway, ack: false)
        )
        self.context?.write(self.wrapOutboundOut(pingFrame), promise: nil)
      }

      self.context?.flush()
    }

    // Close the channel, if necessary.
    if operations.shouldCloseChannel, let context = self.context {
      // Close on the next event-loop tick so we don't drop any events which are
      // currently being processed.
      context.eventLoop.execute {
        self.stateMachine.logger.debug(
          "closing connection",
          metadata: ["connection_age_secs": .stringConvertible(self.connectionAgeInSeconds)]
        )
        context.close(mode: .all, promise: nil)
      }
    }
  }

  private func handlePingAction(_ action: PingHandler.Action) {
    switch action {
    case .none:
      ()

    case .ack:
      // NIO's HTTP2 handler acks for us so this is a no-op. Log so it doesn't appear that we are
      // ignoring pings.
      self.stateMachine.logger.debug(
        "sending PING frame",
        metadata: [MetadataKey.h2PingAck: "true"]
      )

    case .cancelScheduledTimeout:
      self.scheduledClose?.cancel()
      self.scheduledClose = nil

    case let .schedulePing(delay, timeout):
      self.schedulePing(in: delay, timeout: timeout)

    case let .reply(framePayload):
      switch framePayload {
      case .ping(_, let ack):
        self.stateMachine.logger.debug(
          "sending PING frame",
          metadata: [MetadataKey.h2PingAck: "\(ack)"]
        )
      default:
        ()
      }
      let frame = HTTP2Frame(streamID: .rootStream, payload: framePayload)
      self.context?.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)

    case .ratchetDownLastSeenStreamID:
      self.perform(operations: self.stateMachine.ratchetDownGoAwayStreamID())
    }
  }

  private func schedulePing(in delay: TimeAmount, timeout: TimeAmount) {
    guard delay != .nanoseconds(.max) else {
      return
    }

    self.stateMachine.logger.debug(
      "scheduled keepalive pings",
      metadata: [MetadataKey.intervalMs: "\(delay.milliseconds)"]
    )

    self.scheduledPing = self.context?.eventLoop.scheduleRepeatedTask(
      initialDelay: delay,
      delay: delay
    ) { _ in
      let action = self.pingHandler.pingFired()
      if case .none = action { return }
      self.handlePingAction(action)
      // `timeout` is less than `interval`, guaranteeing that the close task
      // will be fired before a new ping is triggered.
      assert(timeout < delay, "`timeout` must be less than `interval`")
      self.scheduleClose(in: timeout)
    }
  }

  private func scheduleClose(in timeout: TimeAmount) {
    self.scheduledClose = self.context?.eventLoop.scheduleTask(in: timeout) {
      self.stateMachine.logger.debug("keepalive timer expired")
      self.perform(operations: self.stateMachine.shutdownNow())
    }
  }

  private func idleTimeoutFired() {
    self.perform(operations: self.stateMachine.idleTimeoutTaskFired())
  }

  func handlerAdded(context: ChannelHandlerContext) {
    self.context = context
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let created = event as? NIOHTTP2StreamCreatedEvent {
      self.perform(operations: self.stateMachine.streamCreated(withID: created.streamID))
      self.handlePingAction(self.pingHandler.streamCreated())
      self.mode.connectionManager?.streamOpened()
      context.fireUserInboundEventTriggered(event)
    } else if let closed = event as? StreamClosedEvent {
      self.perform(operations: self.stateMachine.streamClosed(withID: closed.streamID))
      self.handlePingAction(self.pingHandler.streamClosed())
      self.mode.connectionManager?.streamClosed()
      context.fireUserInboundEventTriggered(event)
    } else if event is ChannelShouldQuiesceEvent {
      self.perform(operations: self.stateMachine.initiateGracefulShutdown())
      // Swallow this event.
    } else if case let .handshakeCompleted(negotiatedProtocol) = event as? TLSUserEvent {
      let tlsVersion = try? context.channel.getTLSVersionSync()
      self.stateMachine.logger.debug(
        "TLS handshake completed",
        metadata: [
          "alpn": "\(negotiatedProtocol ?? "nil")",
          "tls_version": "\(tlsVersion.map(String.init(describing:)) ?? "nil")",
        ]
      )
      context.fireUserInboundEventTriggered(event)
    } else {
      #if canImport(Network)
      if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
        if let waitsForConnectivity = event as? NIOTSNetworkEvents.WaitingForConnectivity {
          self.mode.connectionManager?.channelError(waitsForConnectivity.transientError)
        }
      }
      #endif

      context.fireUserInboundEventTriggered(event)
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    // No state machine action here.
    self.mode.connectionManager?.channelError(error)
    context.fireErrorCaught(error)
  }

  func channelActive(context: ChannelHandlerContext) {
    self.stateMachine.logger.addIPAddressMetadata(
      local: context.localAddress,
      remote: context.remoteAddress
    )

    // No state machine action here.
    switch self.mode {
    case let .client(connectionManager, multiplexer):
      connectionManager.channelActive(channel: context.channel, multiplexer: multiplexer)
    case .server:
      ()
    }
    context.fireChannelActive()
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.perform(operations: self.stateMachine.channelInactive())
    self.scheduledPing?.cancel()
    self.scheduledClose?.cancel()
    self.scheduledPing = nil
    self.scheduledClose = nil
    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)

    switch frame.payload {
    case let .goAway(lastStreamID, errorCode, _):
      self.stateMachine.logger.debug(
        "received GOAWAY frame",
        metadata: [
          MetadataKey.h2GoAwayLastStreamID: "\(Int(lastStreamID))",
          MetadataKey.h2GoAwayError: "\(errorCode.networkCode)",
        ]
      )
      self.perform(operations: self.stateMachine.receiveGoAway())
    case let .settings(.settings(settings)):
      self.perform(operations: self.stateMachine.receiveSettings(settings))
    case let .ping(data, ack):
      self.stateMachine.logger.debug(
        "received PING frame",
        metadata: [MetadataKey.h2PingAck: "\(ack)"]
      )
      self.handlePingAction(self.pingHandler.read(pingData: data, ack: ack))
    default:
      // We're not interested in other events.
      ()
    }

    context.fireChannelRead(data)
  }
}

extension HTTP2SettingsParameter {
  internal var loggingMetadataKey: String {
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

extension TimeAmount {
  fileprivate var milliseconds: Int64 {
    self.nanoseconds / 1_000_000
  }
}
