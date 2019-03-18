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
    serviceProviders: [CallHandlerProvider],
    errorDelegate: ServerErrorDelegate? = LoggingServerErrorDelegate()
  ) -> EventLoopFuture<GRPCServer> {
    let servicesByName = Dictionary(uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) })
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify a backlog to avoid overloading the server.
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        channel.pipeline.addHandler(HTTPProtocolSwitcher { channel in
          channel.pipeline.addHandlers(HTTP1ToRawGRPCServerCodec(),
                                       GRPCChannelHandler(servicesByName: servicesByName, errorDelegate: errorDelegate))
        })
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

    return bootstrap.bind(host: hostname, port: port)
      .map { GRPCServer(channel: $0, errorDelegate: errorDelegate) }
  }

  private let channel: Channel
  private var errorDelegate: ServerErrorDelegate?

  private init(channel: Channel, errorDelegate: ServerErrorDelegate?) {
    self.channel = channel

    // Maintain a strong reference to ensure it lives as long as the server.
    self.errorDelegate = errorDelegate

    // nil out errorDelegate to avoid retain cycles.
    onClose.whenComplete { _ in
      self.errorDelegate = nil
    }
  }

  /// Fired when the server shuts down.
  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  /// Shut down the server; this should be called to avoid leaking resources.
  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}
