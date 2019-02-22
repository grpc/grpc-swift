import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2

/// Wrapper object to manage the lifecycle of a gRPC server.
public final class GRPCServer {
  /// Starts up a server that serves the given providers.
  ///
  /// - Returns: A future that is completed when the server has successfully started up.
  public static func start(
    hostname: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    serviceProviders: [CallHandlerProvider]) -> EventLoopFuture<GRPCServer> {
    let servicesByName = Dictionary(uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) })
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify a backlog to avoid overloading the server.
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        return channel.pipeline.add(handler: HTTPProtocolSwitcher {
          channel -> EventLoopFuture<Void> in
          return channel.pipeline.add(handler: HTTP1ToRawGRPCServerCodec())
            .then { channel.pipeline.add(handler: GRPCChannelHandler(servicesByName: servicesByName)) }
        })
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

    return bootstrap.bind(host: hostname, port: port)
      .map { GRPCServer(channel: $0) }
  }

  private let channel: Channel

  private init(channel: Channel) {
    self.channel = channel
  }

  /// Fired when the server shuts down.
  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}
