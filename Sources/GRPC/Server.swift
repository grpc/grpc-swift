import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL

/// Wrapper object to manage the lifecycle of a gRPC server.
///
/// The pipeline is configured in three stages detailed below. Note: handlers marked with
/// a '*' are responsible for handling errors.
///
/// 1. Initial stage, prior to HTTP protocol detection.
///
///                           ┌───────────────────────────┐
///                           │   HTTPProtocolSwitcher*   │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                           ┌─┴───────────────────────▼─┐
///                           │       NIOSSLHandler       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                             │                       ▼
///
///    The NIOSSLHandler is optional and depends on how the framework user has configured
///    their server. The HTTPProtocolSwitched detects which HTTP version is being used and
///    configures the pipeline accordingly.
///
/// 2. HTTP version detected. "HTTP Handlers" depends on the HTTP version determined by
///    HTTPProtocolSwitcher. All of these handlers are provided by NIO except for the
///    WebCORSHandler which is used for HTTP/1.
///
///                           ┌───────────────────────────┐
///                           │    GRPCChannelHandler*    │
///                           └─▲───────────────────────┬─┘
///     RawGRPCServerRequestPart│                       │RawGRPCServerResponsePart
///                           ┌─┴───────────────────────▼─┐
///                           │ HTTP1ToRawGRPCServerCodec │
///                           └─▲───────────────────────┬─┘
///        HTTPServerRequestPart│                       │HTTPServerResponsePart
///                           ┌─┴───────────────────────▼─┐
///                           │       HTTP Handlers       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                           ┌─┴───────────────────────▼─┐
///                           │       NIOSSLHandler       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                             │                       ▼
///
///    The GPRCChannelHandler resolves the request head and configures the rest of the pipeline
///    based on the RPC call being made.
///
/// 3. The call has been resolved and is a function that this server can handle. Responses are
///    written into `BaseCallHandler` by a user-implemented `CallHandlerProvider`.
///
///                           ┌───────────────────────────┐
///                           │     BaseCallHandler*      │
///                           └─▲───────────────────────┬─┘
///    GRPCServerRequestPart<T1>│                       │GRPCServerResponsePart<T2>
///                           ┌─┴───────────────────────▼─┐
///                           │      GRPCServerCodec      │
///                           └─▲───────────────────────┬─┘
///     RawGRPCServerRequestPart│                       │RawGRPCServerResponsePart
///                           ┌─┴───────────────────────▼─┐
///                           │ HTTP1ToRawGRPCServerCodec │
///                           └─▲───────────────────────┬─┘
///        HTTPServerRequestPart│                       │HTTPServerResponsePart
///                           ┌─┴───────────────────────▼─┐
///                           │       HTTP Handlers       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                           ┌─┴───────────────────────▼─┐
///                           │       NIOSSLHandler       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                             │                       ▼
///
public final class Server {
  /// Starts up a server that serves the given providers.
  ///
  /// - Returns: A future that is completed when the server has successfully started up.
  public static func start(
    hostname: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    serviceProviders: [CallHandlerProvider],
    errorDelegate: ServerErrorDelegate? = LoggingServerErrorDelegate(),
    tls tlsMode: TLSMode = .none
  ) throws -> EventLoopFuture<Server> {
    let servicesByName = Dictionary(uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) })
    let bootstrap = ServerBootstrap(group: eventLoopGroup)
      // Specify a backlog to avoid overloading the server.
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        let protocolSwitcherHandler = HTTPProtocolSwitcher(errorDelegate: errorDelegate) { channel -> EventLoopFuture<Void> in
          channel.pipeline.addHandlers(HTTP1ToRawGRPCServerCodec(),
                                       GRPCChannelHandler(servicesByName: servicesByName, errorDelegate: errorDelegate))
        }

        return configureTLS(mode: tlsMode, channel: channel).flatMap {
          channel.pipeline.addHandler(protocolSwitcherHandler)
        }
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

    return bootstrap.bind(host: hostname, port: port)
      .map { Server(channel: $0, errorDelegate: errorDelegate) }
  }

  /// Configure an SSL handler on the channel, if one is provided.
  ///
  /// - Parameters:
  ///   - mode: TLS mode to run the server in.
  ///   - channel: The channel on which to add the SSL handler.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  private static func configureTLS(mode: TLSMode, channel: Channel) -> EventLoopFuture<Void> {
    guard let sslContext = mode.sslContext else {
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

  public let channel: Channel
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

extension Server {
  public enum TLSMode {
    case none
    case custom(NIOSSLContext)

    var sslContext: NIOSSLContext? {
      switch self {
      case .none:
        return nil

      case .custom(let context):
        return context
      }
    }
  }
}
