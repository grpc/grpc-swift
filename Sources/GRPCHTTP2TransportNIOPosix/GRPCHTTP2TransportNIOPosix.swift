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
import NIOSSL

extension HTTP2ServerTransport {
  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public struct Posix: ServerTransport {
    private let configuration: Config
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let serverQuiescingHelper: ServerQuiescingHelper

    init(configuration: Config) {
      self.configuration = configuration
      self.eventLoopGroup = MultiThreadedEventLoopGroup(
        numberOfThreads: self.configuration.http2.maxConcurrentStreams // TODO: not sure this is the right value to use, or if we should maybe just get the EL from the caller in the init
      )
      self.serverQuiescingHelper = ServerQuiescingHelper(group: self.eventLoopGroup)
    }

    public func listen(
      _ streamHandler: @escaping (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      let serverChannel = try await ServerBootstrap(group: self.eventLoopGroup)
        .serverChannelInitializer { channel in
          let quiescingHandler = self.serverQuiescingHelper.makeServerChannelHandler(channel: channel)
          return channel.pipeline.addHandler(quiescingHandler)
        }
        .bind(
          to: self.configuration.connection.socketAddress,
          childChannelInitializer: { channel in
            channel.eventLoop.makeCompletedFuture {
              if self.configuration.http2.useTLS, let tlsConfiguration = configuration.tlsConfiguration {
                let nioSSLContext = try NIOSSLContext(configuration: tlsConfiguration)
                let nioSSLHandler = NIOSSLServerHandler(context: nioSSLContext)
                try channel.pipeline.syncOperations.addHandler(nioSSLHandler)
              }

              return try channel.pipeline.syncOperations.configureGRPCHTTP2ServerTransportPipeline(
                channel: channel,
                compressionConfiguration: self.configuration.compression,
                keepaliveConfiguration: self.configuration.keepalive,
                idleConfiguration: self.configuration.idle,
                connectionConfiguration: self.configuration.connection,
                http2Configuration: self.configuration.http2
              )
            }
          }
        )

      try await serverChannel.executeThenClose { inbound in
        try await withThrowingDiscardingTaskGroup { serverTaskGroup in
          for try await (connectionChannel, streamMultiplexer) in inbound {
            serverTaskGroup.addTask {
              try await connectionChannel.executeThenClose { connectionInbound, connectionOutbound in
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
    
    /// An optional configuration for TLS.
    ///
    /// - Note: ``http2``'s `useTLS` property must be set as well for TLS to be set up.
    public var tlsConfiguration: TLSConfiguration?
  }
}
