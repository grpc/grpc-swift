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
import NIOHTTP2

/// A namespace for the HTTP/2 server transport.
public enum HTTP2ServerTransport {}

extension HTTP2ServerTransport {
  /// A namespace for HTTP/2 server transport configuration.
  public enum Config {}
}

extension HTTP2ServerTransport.Config {
  public struct Compression: Sendable {
    /// Compression algorithms enabled for inbound messages.
    ///
    /// - Note: ``CompressionAlgorithm/none`` is always supported, even if it isn't set here.
    public var enabledAlgorithms: CompressionAlgorithmSet

    /// Creates a new compression configuration.
    ///
    /// - SeeAlso: ``defaults``.
    public init(enabledAlgorithms: CompressionAlgorithmSet) {
      self.enabledAlgorithms = enabledAlgorithms
    }

    /// Default values, compression is disabled.
    public static var defaults: Self {
      Self(enabledAlgorithms: .none)
    }
  }

  public struct Keepalive: Sendable {
    /// The amount of time to wait after reading data before sending a keepalive ping.
    public var time: TimeAmount

    /// The amount of time the server has to respond to a keepalive ping before the connection is closed.
    public var timeout: TimeAmount

    /// Whether the server allows the client to send keepalive pings when there are no calls in progress.
    public var permitWithoutCalls: Bool

    /// The minimum allowed interval the client is allowed to send keep-alive pings.
    /// Pings more frequent than this interval count as 'strikes' and the connection is closed if there are
    /// too many strikes.
    public var minPingIntervalWithoutCalls: TimeAmount

    /// Creates a new keepalive configuration.
    public init(
      time: TimeAmount,
      timeout: TimeAmount,
      permitWithoutCalls: Bool,
      minPingIntervalWithoutCalls: TimeAmount
    ) {
      self.time = time
      self.timeout = timeout
      self.permitWithoutCalls = permitWithoutCalls
      self.minPingIntervalWithoutCalls = minPingIntervalWithoutCalls
    }
  }

  public struct Idle: Sendable {
    /// The maximum amount of time a connection may be idle before it's closed.
    public var maxTime: TimeAmount

    /// Creates an idle configuration.
    public init(maxTime: TimeAmount) {
      self.maxTime = maxTime
    }

    /// Default values, a 30 minute max idle time.
    public static var defaults: Self {
      Self(maxTime: .seconds(30 * 60))
    }
  }

  public struct Connection: Sendable {
    /// The socket address to bind on.
    public var socketAddress: NIOCore.SocketAddress

    /// The maximum amount of time a connection may exist before being gracefully closed.
    public var maxAge: TimeAmount?

    /// The maximum amount of time that the connection has to close gracefully.
    public var maxGraceTime: TimeAmount
  }

  public struct HTTP2: Sendable {

    /// The maximum frame size to be used in an HTTP/2 connection.
    public var maxFrameSize: Int

    /// Whether TLS is being used or not in the connection.
    public var useTLS: Bool

    /// The target window size for this connection.
    ///
    /// - Note: This will also be set as the initial window size for the connection.
    public var targetWindowSize: Int

    /// The number of concurrent streams on the HTTP/2 connection.
    public var maxConcurrentStreams: Int
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ChannelPipeline.SynchronousOperations {
  public typealias HTTP2ConnectionChannel = NIOAsyncChannel<HTTP2Frame, HTTP2Frame>
  public typealias HTTP2StreamMultiplexer = NIOHTTP2Handler.AsyncStreamMultiplexer<
    (NIOAsyncChannel<RPCRequestPart, RPCResponsePart>, EventLoopFuture<MethodDescriptor>)
  >

  @_spi(Package)
  public func configureGRPCHTTP2ServerTransportPipeline(
    channel: any Channel,
    compressionConfiguration: HTTP2ServerTransport.Config.Compression,
    keepaliveConfiguration: HTTP2ServerTransport.Config.Keepalive,
    idleConfiguration: HTTP2ServerTransport.Config.Idle,
    connectionConfiguration: HTTP2ServerTransport.Config.Connection,
    http2Configuration: HTTP2ServerTransport.Config.HTTP2
  ) throws -> (HTTP2ConnectionChannel, HTTP2StreamMultiplexer) {
    let serverConnectionHandler = ServerConnectionManagementHandler(
      eventLoop: self.eventLoop,
      maxIdleTime: idleConfiguration.maxTime,
      maxAge: connectionConfiguration.maxAge,
      maxGraceTime: connectionConfiguration.maxGraceTime,
      keepaliveTime: keepaliveConfiguration.time,
      keepaliveTimeout: keepaliveConfiguration.timeout,
      allowKeepaliveWithoutCalls: keepaliveConfiguration.permitWithoutCalls,
      minPingIntervalWithoutCalls: keepaliveConfiguration.minPingIntervalWithoutCalls
    )
    let flushNotificationHandler = GRPCServerFlushNotificationHandler(
      serverConnectionManagementHandler: serverConnectionHandler
    )
    try self.addHandler(flushNotificationHandler)

    var http2HandlerConnectionConfiguration = NIOHTTP2Handler.ConnectionConfiguration()
    let http2HandlerHTTP2Settings = HTTP2Settings([
      HTTP2Setting(parameter: .initialWindowSize, value: http2Configuration.targetWindowSize),
      HTTP2Setting(parameter: .maxConcurrentStreams, value: http2Configuration.maxConcurrentStreams)
    ])
    http2HandlerConnectionConfiguration.initialSettings = http2HandlerHTTP2Settings

    var http2HandlerStreamConfiguration = NIOHTTP2Handler.StreamConfiguration()
    http2HandlerStreamConfiguration.targetWindowSize = http2Configuration.targetWindowSize

    let streamMultiplexer = try self.configureAsyncHTTP2Pipeline(
      mode: .server,
      configuration: NIOHTTP2Handler.Configuration(
        connection: http2HandlerConnectionConfiguration,
        stream: http2HandlerStreamConfiguration
      )
    ) { [eventLoop] streamChannel in
      return streamChannel.eventLoop.makeCompletedFuture {
        let streamHandler = GRPCServerStreamHandler(
          scheme: http2Configuration.useTLS ? .https : .http,
          acceptedEncodings: compressionConfiguration.enabledAlgorithms,
          maximumPayloadSize: http2Configuration.maxFrameSize,
          methodDescriptorPromise: eventLoop.makePromise()
        )
        try streamChannel.pipeline.syncOperations.addHandler(streamHandler)

        let asyncStreamChannel = try NIOAsyncChannel<RPCRequestPart, RPCResponsePart>(
          wrappingChannelSynchronously: streamChannel
        )
        return (asyncStreamChannel, streamHandler.methodDescriptorPromise.futureResult)
      }
    }

    try self.addHandler(serverConnectionHandler)

    let connectionChannel = try NIOAsyncChannel<HTTP2Frame, HTTP2Frame>(
      wrappingChannelSynchronously: channel
    )

    return (connectionChannel, streamMultiplexer)
  }
}
