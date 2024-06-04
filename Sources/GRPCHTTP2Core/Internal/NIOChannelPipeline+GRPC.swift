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

import GRPCCore
import NIOCore
import NIOHPACK
import NIOHTTP2

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ChannelPipeline.SynchronousOperations {
  @_spi(Package) public typealias HTTP2ConnectionChannel = NIOAsyncChannel<HTTP2Frame, HTTP2Frame>
  @_spi(Package) public typealias HTTP2StreamMultiplexer = NIOHTTP2Handler.AsyncStreamMultiplexer<
    (NIOAsyncChannel<RPCRequestPart, RPCResponsePart>, EventLoopFuture<MethodDescriptor>)
  >

  @_spi(Package)
  public func configureGRPCServerPipeline(
    channel: any Channel,
    compressionConfig: HTTP2ServerTransport.Config.Compression,
    keepaliveConfig: HTTP2ServerTransport.Config.Keepalive,
    connectionConfig: HTTP2ServerTransport.Config.Connection,
    http2Config: HTTP2ServerTransport.Config.HTTP2,
    rpcConfig: HTTP2ServerTransport.Config.RPC,
    useTLS: Bool
  ) throws -> (HTTP2ConnectionChannel, HTTP2StreamMultiplexer) {
    let serverConnectionHandler = ServerConnectionManagementHandler(
      eventLoop: self.eventLoop,
      maxIdleTime: connectionConfig.maxIdleTime.map { TimeAmount($0) },
      maxAge: connectionConfig.maxAge.map { TimeAmount($0) },
      maxGraceTime: connectionConfig.maxGraceTime.map { TimeAmount($0) },
      keepaliveTime: TimeAmount(keepaliveConfig.time),
      keepaliveTimeout: TimeAmount(keepaliveConfig.timeout),
      allowKeepaliveWithoutCalls: keepaliveConfig.permitWithoutCalls,
      minPingIntervalWithoutCalls: TimeAmount(keepaliveConfig.minPingIntervalWithoutCalls)
    )
    let flushNotificationHandler = GRPCServerFlushNotificationHandler(
      serverConnectionManagementHandler: serverConnectionHandler
    )
    try self.addHandler(flushNotificationHandler)

    var http2HandlerConnectionConfiguration = NIOHTTP2Handler.ConnectionConfiguration()
    var http2HandlerHTTP2Settings = HTTP2Settings([
      HTTP2Setting(parameter: .initialWindowSize, value: http2Config.targetWindowSize),
      HTTP2Setting(parameter: .maxFrameSize, value: http2Config.maxFrameSize),
      HTTP2Setting(parameter: .maxHeaderListSize, value: HPACKDecoder.defaultMaxHeaderListSize),
    ])
    if let maxConcurrentStreams = http2Config.maxConcurrentStreams {
      http2HandlerHTTP2Settings.append(
        HTTP2Setting(parameter: .maxConcurrentStreams, value: maxConcurrentStreams)
      )
    }
    http2HandlerConnectionConfiguration.initialSettings = http2HandlerHTTP2Settings

    var http2HandlerStreamConfiguration = NIOHTTP2Handler.StreamConfiguration()
    http2HandlerStreamConfiguration.targetWindowSize = http2Config.targetWindowSize

    let streamMultiplexer = try self.configureAsyncHTTP2Pipeline(
      mode: .server,
      configuration: NIOHTTP2Handler.Configuration(
        connection: http2HandlerConnectionConfiguration,
        stream: http2HandlerStreamConfiguration
      )
    ) { streamChannel in
      return streamChannel.eventLoop.makeCompletedFuture {
        let methodDescriptorPromise = streamChannel.eventLoop.makePromise(of: MethodDescriptor.self)
        let streamHandler = GRPCServerStreamHandler(
          scheme: useTLS ? .https : .http,
          acceptedEncodings: compressionConfig.enabledAlgorithms,
          maximumPayloadSize: rpcConfig.maxRequestPayloadSize,
          methodDescriptorPromise: methodDescriptorPromise
        )
        try streamChannel.pipeline.syncOperations.addHandler(streamHandler)

        let asyncStreamChannel = try NIOAsyncChannel<RPCRequestPart, RPCResponsePart>(
          wrappingChannelSynchronously: streamChannel
        )
        return (asyncStreamChannel, methodDescriptorPromise.futureResult)
      }
    }

    try self.addHandler(serverConnectionHandler)

    let connectionChannel = try NIOAsyncChannel<HTTP2Frame, HTTP2Frame>(
      wrappingChannelSynchronously: channel
    )

    return (connectionChannel, streamMultiplexer)
  }
}

extension ChannelPipeline.SynchronousOperations {
  @_spi(Package)
  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public func configureGRPCClientPipeline(
    channel: Channel,
    config: GRPCChannel.Config
  ) throws -> (
    NIOAsyncChannel<ClientConnectionEvent, Void>,
    NIOHTTP2Handler.AsyncStreamMultiplexer<Void>
  ) {
    // Window size which mustn't exceed 2^32 - 1 (RFC 9113 § 6.1.3).
    let clampedTargetWindowSize = min(config.http2.targetWindowSize, (1 << 31) - 1)

    // Max frame size must be in the range 2^14 ..< 2^24 (RFC 9113 § 6.1.3).
    let clampedMaxFrameSize: Int
    if config.http2.maxFrameSize >= (1 << 24) {
      clampedMaxFrameSize = (1 << 24) - 1
    } else if config.http2.maxFrameSize < (1 << 14) {
      clampedMaxFrameSize = (1 << 14)
    } else {
      clampedMaxFrameSize = config.http2.maxFrameSize
    }

    // Use NIOs defaults as a starting point.
    var http2 = NIOHTTP2Handler.Configuration()
    http2.stream.targetWindowSize = clampedTargetWindowSize
    http2.connection.initialSettings = [
      // Disallow servers from creating push streams.
      HTTP2Setting(parameter: .enablePush, value: 0),
      // Set the initial window size and max frame size to the clamped configured values.
      HTTP2Setting(parameter: .initialWindowSize, value: clampedTargetWindowSize),
      HTTP2Setting(parameter: .maxFrameSize, value: clampedMaxFrameSize),
      // Use NIOs default max header list size (16kB)
      HTTP2Setting(parameter: .maxHeaderListSize, value: HPACKDecoder.defaultMaxHeaderListSize),
    ]

    let multiplexer = try self.configureAsyncHTTP2Pipeline(
      mode: .client,
      configuration: http2
    ) { stream in
      // Shouldn't happen, push-promises are disabled so the server shouldn't be able to
      // open streams.
      stream.close()
    }

    let connectionHandler = ClientConnectionHandler(
      eventLoop: self.eventLoop,
      maxIdleTime: config.idle.map { TimeAmount($0.maxTime) },
      keepaliveTime: config.keepalive.map { TimeAmount($0.time) },
      keepaliveTimeout: config.keepalive.map { TimeAmount($0.timeout) },
      keepaliveWithoutCalls: config.keepalive?.permitWithoutCalls ?? false
    )

    try self.addHandler(connectionHandler)

    let connection = try NIOAsyncChannel(
      wrappingChannelSynchronously: channel,
      configuration: NIOAsyncChannel.Configuration(
        inboundType: ClientConnectionEvent.self,
        outboundType: Void.self
      )
    )

    return (connection, multiplexer)
  }
}
