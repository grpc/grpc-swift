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
    private let config: Config
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let serverQuiescingHelper: ServerQuiescingHelper

    public init(
      address: GRPCHTTP2Core.SocketAddress,
      config: Config = .defaults,
      eventLoopGroup: MultiThreadedEventLoopGroup = .singletonMultiThreadedEventLoopGroup
    ) {
      self.address = address
      self.config = config
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
        .bind(to: self.address) { channel in
          channel.eventLoop.makeCompletedFuture {
            return try channel.pipeline.syncOperations.configureGRPCServerPipeline(
              channel: channel,
              compressionConfig: self.config.compression,
              connectionConfig: self.config.connection,
              http2Config: self.config.http2,
              rpcConfig: self.config.rpc,
              useTLS: false
            )
          }
        }

      try await serverChannel.executeThenClose { inbound in
        try await withThrowingDiscardingTaskGroup { serverTaskGroup in
          for try await (connectionChannel, streamMultiplexer) in inbound {
            serverTaskGroup.addTask {
              try await connectionChannel
                .executeThenClose { connectionInbound, connectionOutbound in
                  await withDiscardingTaskGroup { connectionTaskGroup in
                    connectionTaskGroup.addTask {
                      do {
                        for try await _ in connectionInbound {}
                      } catch {
                        // We don't want to close the channel if one connection throws.
                        return
                      }
                    }

                    connectionTaskGroup.addTask {
                      await withDiscardingTaskGroup { streamTaskGroup in
                        do {
                          for try await (http2Stream, methodDescriptor) in streamMultiplexer.inbound
                          {
                            streamTaskGroup.addTask {
                              // It's okay to ignore these errors:
                              // - If we get an error because the http2Stream failed to close, then there's nothing we can do
                              // - If we get an error because the inner closure threw, then the only possible scenario in which
                              // that could happen is if methodDescriptor.get() throws - in which case, it means we never got
                              // the RPC metadata, which means we can't do anything either and it's okay to just kill the stream.
                              try? await http2Stream.executeThenClose { inbound, outbound in
                                guard let descriptor = try? await methodDescriptor.get() else {
                                  return
                                }
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
                                await streamHandler(rpcStream)
                              }
                            }
                          }
                        } catch {
                          // We don't want to close the whole connection if one stream throws.
                          return
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
    /// Compression configuration.
    public var compression: HTTP2ServerTransport.Config.Compression
    /// Connection configuration.
    public var connection: HTTP2ServerTransport.Config.Connection
    /// HTTP2 configuration.
    public var http2: HTTP2ServerTransport.Config.HTTP2
    /// RPC configuration.
    public var rpc: HTTP2ServerTransport.Config.RPC

    /// Construct a new `Config`.
    /// - Parameters:
    ///   - compression: Compression configuration.
    ///   - connection: Connection configuration.
    ///   - http2: HTTP2 configuration.
    ///   - rpc: RPC configuration.
    public init(
      compression: HTTP2ServerTransport.Config.Compression,
      connection: HTTP2ServerTransport.Config.Connection,
      http2: HTTP2ServerTransport.Config.HTTP2,
      rpc: HTTP2ServerTransport.Config.RPC
    ) {
      self.compression = compression
      self.connection = connection
      self.http2 = http2
      self.rpc = rpc
    }

    /// Default values for the different configurations.
    public static var defaults: Self {
      Self(
        compression: .defaults,
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
      self = try Self(ipv4)
    } else if let ipv6 = socketAddress.ipv6 {
      self = try Self(ipv6)
    } else if let unixDomainSocket = socketAddress.unixDomainSocket {
      self = try Self(unixDomainSocket)
    } else {
      throw RPCError(
        code: .internalError,
        message:
          "Unsupported mapping to NIOCore/SocketAddress for GRPCHTTP2Core/SocketAddress: \(socketAddress)."
      )
    }
  }
}

extension ServerBootstrap {
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  fileprivate func bind<Output: Sendable>(
    to address: GRPCHTTP2Core.SocketAddress,
    childChannelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Output>
  ) async throws -> NIOAsyncChannel<Output, Never> {
    if let virtualSocket = address.virtualSocket {
      return try await self.bind(
        to: VsockAddress(virtualSocket),
        childChannelInitializer: childChannelInitializer
      )
    } else {
      return try await self.bind(
        to: NIOCore.SocketAddress(address),
        childChannelInitializer: childChannelInitializer
      )
    }
  }
}
