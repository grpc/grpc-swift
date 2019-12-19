/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import NIO
import NIOHTTP2
import Logging

/// The purpose of this channel handler is to observe the initial settings frame on the root stream.
/// This is an indication that the connection has become `.ready`. When this happens this handler
/// will remove itself from the pipeline.
class InitialSettingsObservingHandler: ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = HTTP2Frame
  typealias InboundOut = HTTP2Frame

  private let connectivityStateMonitor: ConnectivityStateMonitor
  private let logger = Logger(subsystem: .clientChannel)

  init(connectivityStateMonitor: ConnectivityStateMonitor) {
    self.connectivityStateMonitor = connectivityStateMonitor
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)

    if frame.streamID == .rootStream, case .settings(.settings) = frame.payload {
      self.logger.debug("observed initial settings frame on the root stream")
      self.connectivityStateMonitor.state = .ready

      let remoteAddressDescription = context.channel.remoteAddress.map { "\($0)" } ?? "n/a"
      self.logger.info("gRPC connection to \(remoteAddressDescription) on \(context.eventLoop) ready")

      // We're no longer needed at this point, remove ourselves from the pipeline.
      self.logger.debug("removing 'InitialSettingsObservingHandler' from the channel")
      context.pipeline.removeHandler(self, promise: nil)
    }

    // We should always forward the frame.
    context.fireChannelRead(data)
  }
}
