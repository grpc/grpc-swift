import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL

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
    errorDelegate: ServerErrorDelegate? = LoggingServerErrorDelegate(),
    sslContext: NIOSSLContext? = nil
  ) throws -> EventLoopFuture<GRPCServer> {
    let servicesByName = Dictionary(uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) })
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify a backlog to avoid overloading the server.
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        let protocolSwitcherHandler = HTTPProtocolSwitcher { channel -> EventLoopFuture<Void> in
          channel.pipeline.addHandlers(HTTP1ToRawGRPCServerCodec(),
                                       GRPCChannelHandler(servicesByName: servicesByName, errorDelegate: errorDelegate))
        }

        return configureSSL(sslContext: sslContext, channel: channel).flatMap {
          channel.pipeline.addHandler(protocolSwitcherHandler)
        }
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

    return bootstrap.bind(host: hostname, port: port)
      .map { GRPCServer(channel: $0, errorDelegate: errorDelegate) }
  }

  /// Configure an SSL handler on the channel, if one is provided.
  ///
  /// - Parameters:
  ///   - sslContext: SSL context to use when creating the handler.
  ///   - channel: The channel on which to add the SSL handler.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  private static func configureSSL(sslContext: NIOSSLContext?, channel: Channel) -> EventLoopFuture<Void> {
    guard let sslContext = sslContext else {
      return channel.eventLoop.makeSucceededFuture(())
    }

    let handlerAddedPromise: EventLoopPromise<Void> = channel.eventLoop.makePromise()

    do {
      channel.pipeline.addHandler(try NIOSSLServerHandler(context: sslContext)).cascade(to: handlerAddedPromise)
    } catch {
      handlerAddedPromise.fail(error)
    }

    return handlerAddedPromise.futureResult
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
