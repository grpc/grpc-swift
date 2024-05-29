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
@_spi(Package) import GRPCHTTP2Core
import NIOCore
import NIOExtras
import NIOPosix

extension HTTP2ServerTransport {
  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public struct Posix: ServerTransport {
    private let address: GRPCHTTP2Core.SocketAddress
    private let configuration: Config
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let serverQuiescingHelper: ServerQuiescingHelper

    public init(
      address: GRPCHTTP2Core.SocketAddress,
      config: Config,
      eventLoopGroup: MultiThreadedEventLoopGroup = .singletonMultiThreadedEventLoopGroup
    ) {
      self.address = address
      self.configuration = config
      self.eventLoopGroup = eventLoopGroup
      self.serverQuiescingHelper = ServerQuiescingHelper(group: self.eventLoopGroup)
    }

    public func listen(
      _ streamHandler: @escaping (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      let serverChannel = try await ServerBootstrap(group: self.eventLoopGroup)
        .serverChannelInitializer { channel in
          let quiescingHandler = self.serverQuiescingHelper.makeServerChannelHandler(
            channel: channel
          )
          return channel.pipeline.addHandler(quiescingHandler)
        }
        .bind(to: NIOCore.SocketAddress(self.address)) { channel in
          channel.eventLoop.makeCompletedFuture {
            return try channel.pipeline.syncOperations.configureGRPCServerPipeline(
              channel: channel,
              compressionConfig: self.configuration.compression,
              keepaliveConfig: self.configuration.keepalive,
              idleConfig: self.configuration.idle,
              connectionConfig: self.configuration.connection,
              http2Config: self.configuration.http2,
              rpcConfig: self.configuration.rpc,
              useTLS: false
            )
          }
        }

      try await serverChannel.executeThenClose { inbound in
        try await withThrowingDiscardingTaskGroup { serverTaskGroup in
          for try await (connectionChannel, streamMultiplexer) in inbound {
            serverTaskGroup.addTask {
              try await connectionChannel.executeThenClose {
                connectionInbound,
                connectionOutbound in
                try await withThrowingDiscardingTaskGroup { connectionTaskGroup in
                  connectionTaskGroup.addTask {
                    for try await _ in connectionInbound {}
                  }

                  connectionTaskGroup.addTask {
                    try await withThrowingDiscardingTaskGroup { streamTaskGroup in
                      for try await (http2Stream, methodDescriptor) in streamMultiplexer.inbound {
                        try await http2Stream.executeThenClose { inbound, outbound in
                          let descriptor = try await methodDescriptor.get()
                          let rpcStream = RPCStream(
                            descriptor: descriptor,
                            inbound: RPCAsyncSequence(wrapping: inbound),
                            outbound: RPCWriter.Closable(
                              wrapping: ServerConnection.Stream.Outbound(
                                responseWriter: outbound,
                                http2Stream: http2Stream
                              )
                            )
                          )

                          streamTaskGroup.addTask {
                            await streamHandler(rpcStream)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    public func stopListening() {
      self.serverQuiescingHelper.initiateShutdown(promise: nil)
    }
  }

}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension HTTP2ServerTransport.Posix {
  /// Configuration for the ``GRPCHTTP2TransportNIOPosix/GRPCHTTP2Core/HTTP2ServerTransport/Posix``.
  public struct Config: Sendable {
    public var compression: HTTP2ServerTransport.Config.Compression
    public var keepalive: HTTP2ServerTransport.Config.Keepalive
    public var idle: HTTP2ServerTransport.Config.Idle
    public var connection: HTTP2ServerTransport.Config.Connection
    public var http2: HTTP2ServerTransport.Config.HTTP2
    public var rpc: HTTP2ServerTransport.Config.RPC

    /// Construct a new `Config`.
    /// - Parameters:
    ///   - compression: Compression configuration.
    ///   - keepalive: Keepalive configuration.
    ///   - idle: Idle configuration.
    ///   - connection: Connection configuration.
    ///   - http2: HTTP2 configuration.
    ///   - rpc: RPC configuration.
    public init(
      compression: HTTP2ServerTransport.Config.Compression = .defaults,
      keepalive: HTTP2ServerTransport.Config.Keepalive = .defaults,
      idle: HTTP2ServerTransport.Config.Idle = .defaults,
      connection: HTTP2ServerTransport.Config.Connection = .defaults,
      http2: HTTP2ServerTransport.Config.HTTP2 = .defaults,
      rpc: HTTP2ServerTransport.Config.RPC = .defaults
    ) {
      self.compression = compression
      self.keepalive = keepalive
      self.idle = idle
      self.connection = connection
      self.http2 = http2
      self.rpc = rpc
    }

    /// Default values for the different configurations.
    public static var defaults: Self {
      Self(
        compression: .defaults,
        keepalive: .defaults,
        idle: .defaults,
        connection: .defaults,
        http2: .defaults,
        rpc: .defaults
      )
    }
  }
}

extension NIOCore.SocketAddress {
  fileprivate init(_ socketAddress: GRPCHTTP2Core.SocketAddress) throws {
    if let ipv4 = socketAddress.ipv4 {
      self = try Self(ipAddress: ipv4.host, port: ipv4.port)
    } else if let ipv6 = socketAddress.ipv6 {
      self = try Self(ipAddress: ipv6.host, port: ipv6.port)
    } else if let unixDomainSocket = socketAddress.unixDomainSocket {
      self = try Self(unixDomainSocketPath: unixDomainSocket.path)
    } else {
      throw RPCError(code: .internalError, message: "Unsupported socket address.")
    }
  }
}
