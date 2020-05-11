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

internal class ClientConnectivityHandler: ChannelInboundHandler {
  typealias InboundIn = HTTP2Frame

  private var connectionManager: ConnectionManager
  private let idleTimeout: TimeAmount

  private var activeStreams = 0
  private var scheduledIdle: Scheduled<Void>? = nil
  private var isReady = false

  init(connectionManager: ConnectionManager, idleTimeout: TimeAmount = .minutes(5)) {
    self.connectionManager = connectionManager
    self.idleTimeout = idleTimeout
  }

  func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if event is NIOHTTP2StreamCreatedEvent {
      // We have a stream: don't go idle
      self.scheduledIdle?.cancel()
      self.activeStreams += 1
    } else if event is StreamClosedEvent {
      self.activeStreams -= 1
      // No active streams: go idle soon.
      if self.activeStreams == 0 {
        self.scheduledIdle = context.eventLoop.scheduleTask(in: self.idleTimeout) {
          self.idle(context: context)
        }
      }
    }

    context.fireUserInboundEventTriggered(event)
  }

  func channelActive(context: ChannelHandlerContext) {
    self.connectionManager.channelActive(channel: context.channel)
    context.fireChannelActive()
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.scheduledIdle?.cancel()
    self.connectionManager.channelInactive()
    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)

    if frame.streamID == .rootStream {
      switch frame.payload {
      case .settings where !self.isReady:
        self.isReady = true

        let remoteAddressDescription = context.channel.remoteAddress.map { "\($0)" } ?? "n/a"
        self.connectionManager.logger.info("gRPC connection ready", metadata: [
          "remote_address": "\(remoteAddressDescription)",
          "event_loop": "\(context.eventLoop)"
        ])

        // Start the idle timeout.
        self.scheduledIdle = context.eventLoop.scheduleTask(in: self.idleTimeout) {
          self.idle(context: context)
        }

        self.connectionManager.ready()

      case .goAway where self.activeStreams == 0:
        self.idle(context: context)

      default:
        ()
      }
    }

    context.fireChannelRead(data)
  }

  private func idle(context: ChannelHandlerContext) {
    assert(self.activeStreams == 0)
    self.connectionManager.idle()
    context.close(mode: .all, promise: nil)
  }
}
