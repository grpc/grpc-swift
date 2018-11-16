import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2

// Wrapper object to manage the lifecycle of a gRPC server.
public final class GRPCServer {
  public static func start(
    hostname: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    serviceProviders: [CallHandlerProvider]) -> EventLoopFuture<GRPCServer> {
    let servicesByName = Dictionary(uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) })
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify backlog and enable SO_REUSEADDR for the server itself
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        //! FIXME: Add an option for gRPC-via-HTTP1 (pPRC).
        return channel.pipeline.add(handler: HTTP2Parser(mode: .server)).then {
          let multiplexer = HTTP2StreamMultiplexer { (channel, streamID) -> EventLoopFuture<Void> in
            return channel.pipeline.add(handler: HTTP2ToHTTP1ServerCodec(streamID: streamID))
              .then { channel.pipeline.add(handler: HTTP1ToRawGRPCServerCodec()) }
              .then { channel.pipeline.add(handler: GRPCChannelHandler(servicesByName: servicesByName)) }
          }

          return channel.pipeline.add(handler: multiplexer)
        }
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)

    return bootstrap.bind(host: hostname, port: port)
      .map { GRPCServer(channel: $0) }
  }

  fileprivate let channel: Channel

  fileprivate init(channel: Channel) {
    self.channel = channel
  }

  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}
