/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import Logging
import NIOCore
import NIOExtras
import NIOHTTP1
import NIOHTTP2
import NIOPosix
#if canImport(NIOSSL)
import NIOSSL
#endif
import NIOTransportServices
#if canImport(Network)
import Network
#endif

/// Wrapper object to manage the lifecycle of a gRPC server.
///
/// The pipeline is configured in three stages detailed below. Note: handlers marked with
/// a '*' are responsible for handling errors.
///
/// 1. Initial stage, prior to pipeline configuration.
///
///                        ┌─────────────────────────────────┐
///                        │ GRPCServerPipelineConfigurator* │
///                        └────▲───────────────────────┬────┘
///                   ByteBuffer│                       │ByteBuffer
///                           ┌─┴───────────────────────▼─┐
///                           │       NIOSSLHandler       │
///                           └─▲───────────────────────┬─┘
///                   ByteBuffer│                       │ByteBuffer
///                             │                       ▼
///
///    The `NIOSSLHandler` is optional and depends on how the framework user has configured
///    their server. The `GRPCServerPipelineConfigurator` detects which HTTP version is being used
///    (via ALPN if TLS is used or by parsing the first bytes on the connection otherwise) and
///    configures the pipeline accordingly.
///
/// 2. HTTP version detected. "HTTP Handlers" depends on the HTTP version determined by
///    `GRPCServerPipelineConfigurator`. In the case of HTTP/2:
///
///                           ┌─────────────────────────────────┐
///                           │           HTTP2Handler          │
///                           └─▲─────────────────────────────┬─┘
///                   ByteBuffer│                             │ByteBuffer
///                           ┌─┴─────────────────────────────▼─┐
///                           │          NIOSSLHandler          │
///                           └─▲─────────────────────────────┬─┘
///                   ByteBuffer│                             │ByteBuffer
///                             │                             ▼
///
///    The `NIOHTTP2Handler.StreamMultiplexer` provides one `Channel` for each HTTP/2 stream (and thus each
///    RPC).
///
/// 3. The frames for each stream channel are routed by the `HTTP2ToRawGRPCServerCodec` handler to
///    a handler containing the user-implemented logic provided by a `CallHandlerProvider`:
///
///                           ┌─────────────────────────────────┐
///                           │         BaseCallHandler*        │
///                           └─▲─────────────────────────────┬─┘
///        GRPCServerRequestPart│                             │GRPCServerResponsePart
///                           ┌─┴─────────────────────────────▼─┐
///                           │    HTTP2ToRawGRPCServerCodec    │
///                           └─▲─────────────────────────────┬─┘
///      HTTP2Frame.FramePayload│                             │HTTP2Frame.FramePayload
///                             │                             ▼
///
public final class Server {
  /// Makes and configures a `ServerBootstrap` using the provided configuration.
  public class func makeBootstrap(configuration: Configuration) -> ServerBootstrapProtocol {
    let bootstrap = PlatformSupport.makeServerBootstrap(group: configuration.eventLoopGroup)

    // Backlog is only available on `ServerBootstrap`.
    if bootstrap is ServerBootstrap {
      // Specify a backlog to avoid overloading the server.
      _ = bootstrap.serverChannelOption(ChannelOptions.backlog, value: 256)
    }

    #if canImport(NIOSSL)
    // Making a `NIOSSLContext` is expensive, we should only do it once per TLS configuration so
    // we'll do it now, before accepting connections. Unfortunately our API isn't throwing so we'll
    // only surface any error when initializing a child channel.
    //
    // 'nil' means we're not using TLS, or we're using the Network.framework TLS backend. If we're
    // using the Network.framework TLS backend we'll apply the settings just below.
    let sslContext: Result<NIOSSLContext, Error>?

    if let tlsConfiguration = configuration.tlsConfiguration {
      do {
        sslContext = try tlsConfiguration.makeNIOSSLContext().map { .success($0) }
      } catch {
        sslContext = .failure(error)
      }

    } else {
      // No TLS configuration, no SSL context.
      sslContext = nil
    }
    #endif // canImport(NIOSSL)

    #if canImport(Network)
    if let tlsConfiguration = configuration.tlsConfiguration {
      if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *),
         let transportServicesBootstrap = bootstrap as? NIOTSListenerBootstrap {
        _ = transportServicesBootstrap.tlsOptions(from: tlsConfiguration)
      }
    }
    #endif // canImport(Network)

    return bootstrap
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(
        ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
        value: 1
      )
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        var configuration = configuration
        configuration.logger[metadataKey: MetadataKey.connectionID] = "\(UUID().uuidString)"
        configuration.logger.addIPAddressMetadata(
          local: channel.localAddress,
          remote: channel.remoteAddress
        )

        do {
          let sync = channel.pipeline.syncOperations
          #if canImport(NIOSSL)
          if let sslContext = try sslContext?.get() {
            let sslHandler: NIOSSLServerHandler
            if let verify = configuration.tlsConfiguration?.nioSSLCustomVerificationCallback {
              sslHandler = NIOSSLServerHandler(
                context: sslContext,
                customVerificationCallback: verify
              )
            } else {
              sslHandler = NIOSSLServerHandler(context: sslContext)
            }

            try sync.addHandler(sslHandler)
          }
          #endif // canImport(NIOSSL)

          // Configures the pipeline based on whether the connection uses TLS or not.
          try sync.addHandler(GRPCServerPipelineConfigurator(configuration: configuration))

          // Work around the zero length write issue, if needed.
          let requiresZeroLengthWorkaround = PlatformSupport.requiresZeroLengthWriteWorkaround(
            group: configuration.eventLoopGroup,
            hasTLS: configuration.tlsConfiguration != nil
          )
          if requiresZeroLengthWorkaround,
             #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            try sync.addHandler(NIOFilterEmptyWritesHandler())
          }
        } catch {
          return channel.eventLoop.makeFailedFuture(error)
        }

        // Run the debug initializer, if there is one.
        if let debugAcceptedChannelInitializer = configuration.debugChannelInitializer {
          return debugAcceptedChannelInitializer(channel)
        } else {
          return channel.eventLoop.makeSucceededVoidFuture()
        }
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(
        ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
        value: 1
      )
  }

  /// Starts a server with the given configuration. See `Server.Configuration` for the options
  /// available to configure the server.
  public static func start(configuration: Configuration) -> EventLoopFuture<Server> {
    let quiescingHelper = ServerQuiescingHelper(group: configuration.eventLoopGroup)

    return self.makeBootstrap(configuration: configuration)
      .serverChannelInitializer { channel in
        channel.pipeline.addHandler(quiescingHelper.makeServerChannelHandler(channel: channel))
      }
      .bind(to: configuration.target)
      .map { channel in
        Server(
          channel: channel,
          quiescingHelper: quiescingHelper,
          errorDelegate: configuration.errorDelegate
        )
      }
  }

  public let channel: Channel
  private let quiescingHelper: ServerQuiescingHelper
  private var errorDelegate: ServerErrorDelegate?

  private init(
    channel: Channel,
    quiescingHelper: ServerQuiescingHelper,
    errorDelegate: ServerErrorDelegate?
  ) {
    self.channel = channel
    self.quiescingHelper = quiescingHelper

    // Maintain a strong reference to ensure it lives as long as the server.
    self.errorDelegate = errorDelegate

    // If we have an error delegate, add a server channel error handler as well. We don't need to wait for the handler to
    // be added.
    if let errorDelegate = errorDelegate {
      _ = channel.pipeline.addHandler(ServerChannelErrorHandler(errorDelegate: errorDelegate))
    }

    // nil out errorDelegate to avoid retain cycles.
    self.onClose.whenComplete { _ in
      self.errorDelegate = nil
    }
  }

  /// Fired when the server shuts down.
  public var onClose: EventLoopFuture<Void> {
    return self.channel.closeFuture
  }

  /// Initiates a graceful shutdown. Existing RPCs may run to completion, any new RPCs or
  /// connections will be rejected.
  public func initiateGracefulShutdown(promise: EventLoopPromise<Void>?) {
    self.quiescingHelper.initiateShutdown(promise: promise)
  }

  /// Initiates a graceful shutdown. Existing RPCs may run to completion, any new RPCs or
  /// connections will be rejected.
  public func initiateGracefulShutdown() -> EventLoopFuture<Void> {
    let promise = self.channel.eventLoop.makePromise(of: Void.self)
    self.initiateGracefulShutdown(promise: promise)
    return promise.futureResult
  }

  /// Shutdown the server immediately. Active RPCs and connections will be terminated.
  public func close(promise: EventLoopPromise<Void>?) {
    self.channel.close(mode: .all, promise: promise)
  }

  /// Shutdown the server immediately. Active RPCs and connections will be terminated.
  public func close() -> EventLoopFuture<Void> {
    return self.channel.close(mode: .all)
  }
}

public typealias BindTarget = ConnectionTarget

extension Server {
  /// The configuration for a server.
  public struct Configuration {
    /// The target to bind to.
    public var target: BindTarget
    /// The event loop group to run the connection on.
    public var eventLoopGroup: EventLoopGroup

    /// Providers the server should use to handle gRPC requests.
    public var serviceProviders: [CallHandlerProvider] {
      get {
        return Array(self.serviceProvidersByName.values)
      }
      set {
        self
          .serviceProvidersByName = Dictionary(
            uniqueKeysWithValues: newValue
              .map { ($0.serviceName, $0) }
          )
      }
    }

    /// An error delegate which is called when errors are caught. Provided delegates **must not
    /// maintain a strong reference to this `Server`**. Doing so will cause a retain cycle.
    public var errorDelegate: ServerErrorDelegate?

    #if canImport(NIOSSL)
    /// TLS configuration for this connection. `nil` if TLS is not desired.
    @available(*, deprecated, renamed: "tlsConfiguration")
    public var tls: TLS? {
      get {
        return self.tlsConfiguration?.asDeprecatedServerConfiguration
      }
      set {
        self.tlsConfiguration = newValue.map { GRPCTLSConfiguration(transforming: $0) }
      }
    }
    #endif // canImport(NIOSSL)

    public var tlsConfiguration: GRPCTLSConfiguration?

    /// The connection keepalive configuration.
    public var connectionKeepalive = ServerConnectionKeepalive()

    /// The amount of time to wait before closing connections. The idle timeout will start only
    /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start.
    public var connectionIdleTimeout: TimeAmount = .nanoseconds(.max)

    /// The compression configuration for requests and responses.
    ///
    /// If compression is enabled for the server it may be disabled for responses on any RPC by
    /// setting `compressionEnabled` to `false` on the context of the call.
    ///
    /// Compression may also be disabled at the message-level for streaming responses (i.e. server
    /// streaming and bidirectional streaming RPCs) by passing setting `compression` to `.disabled`
    /// in `sendResponse(_:compression)`.
    ///
    /// Defaults to ``ServerMessageEncoding/disabled``.
    public var messageEncoding: ServerMessageEncoding = .disabled

    /// The maximum size in bytes of a message which may be received from a client. Defaults to 4MB.
    public var maximumReceiveMessageLength: Int = 4 * 1024 * 1024 {
      willSet {
        precondition(newValue >= 0, "maximumReceiveMessageLength must be positive")
      }
    }

    /// The HTTP/2 flow control target window size. Defaults to 8MB. Values are clamped between
    /// 1 and 2^31-1 inclusive.
    public var httpTargetWindowSize = 8 * 1024 * 1024 {
      didSet {
        self.httpTargetWindowSize = self.httpTargetWindowSize.clamped(to: 1 ... Int(Int32.max))
      }
    }

    /// The HTTP/2 max number of concurrent streams. Defaults to 100. Must be non-negative.
    public var httpMaxConcurrentStreams: Int = 100 {
      willSet {
        precondition(newValue >= 0, "httpMaxConcurrentStreams must be non-negative")
      }
    }

    /// The HTTP/2 max frame size. Defaults to 16384. Value is clamped between 2^14 and 2^24-1
    /// octets inclusive (the minimum and maximum allowable values - HTTP/2 RFC 7540 4.2).
    public var httpMaxFrameSize: Int = 16384 {
      didSet {
        self.httpMaxFrameSize = self.httpMaxFrameSize.clamped(to: 16384 ... 16_777_215)
      }
    }

    /// The root server logger. Accepted connections will branch from this logger and RPCs on
    /// each connection will use a logger branched from the connections logger. This logger is made
    /// available to service providers via `context`. Defaults to a no-op logger.
    public var logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() })

    /// A channel initializer which will be run after gRPC has initialized each accepted channel.
    /// This may be used to add additional handlers to the pipeline and is intended for debugging.
    /// This is analogous to `NIO.ServerBootstrap.childChannelInitializer`.
    ///
    /// - Warning: The initializer closure may be invoked *multiple times*. More precisely: it will
    ///   be invoked at most once per accepted connection.
    public var debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)?

    /// A calculated private cache of the service providers by name.
    ///
    /// This is how gRPC consumes the service providers internally. Caching this as stored data avoids
    /// the need to recalculate this dictionary each time we receive an rpc.
    internal var serviceProvidersByName: [Substring: CallHandlerProvider]

    /// CORS configuration for gRPC-Web support.
    public var webCORS = Configuration.CORS()

    #if canImport(NIOSSL)
    /// Create a `Configuration` with some pre-defined defaults.
    ///
    /// - Parameters:
    ///   - target: The target to bind to.
    ///   -  eventLoopGroup: The event loop group to run the server on.
    ///   - serviceProviders: An array of `CallHandlerProvider`s which the server should use
    ///       to handle requests.
    ///   - errorDelegate: The error delegate, defaulting to a logging delegate.
    ///   - tls: TLS configuration, defaulting to `nil`.
    ///   - connectionKeepalive: The keepalive configuration to use.
    ///   - connectionIdleTimeout: The amount of time to wait before closing the connection, this is
    ///       indefinite by default.
    ///   - messageEncoding: Message compression configuration, defaulting to no compression.
    ///   - httpTargetWindowSize: The HTTP/2 flow control target window size.
    ///   - logger: A logger. Defaults to a no-op logger.
    ///   - debugChannelInitializer: A channel initializer which will be called for each connection
    ///     the server accepts after gRPC has initialized the channel. Defaults to `nil`.
    @available(*, deprecated, renamed: "default(target:eventLoopGroup:serviceProviders:)")
    public init(
      target: BindTarget,
      eventLoopGroup: EventLoopGroup,
      serviceProviders: [CallHandlerProvider],
      errorDelegate: ServerErrorDelegate? = nil,
      tls: TLS? = nil,
      connectionKeepalive: ServerConnectionKeepalive = ServerConnectionKeepalive(),
      connectionIdleTimeout: TimeAmount = .nanoseconds(.max),
      messageEncoding: ServerMessageEncoding = .disabled,
      httpTargetWindowSize: Int = 8 * 1024 * 1024,
      logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() }),
      debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.serviceProvidersByName = Dictionary(
        uniqueKeysWithValues: serviceProviders.map { ($0.serviceName, $0) }
      )
      self.errorDelegate = errorDelegate
      self.tlsConfiguration = tls.map { GRPCTLSConfiguration(transforming: $0) }
      self.connectionKeepalive = connectionKeepalive
      self.connectionIdleTimeout = connectionIdleTimeout
      self.messageEncoding = messageEncoding
      self.httpTargetWindowSize = httpTargetWindowSize
      self.logger = logger
      self.debugChannelInitializer = debugChannelInitializer
    }
    #endif // canImport(NIOSSL)

    private init(
      eventLoopGroup: EventLoopGroup,
      target: BindTarget,
      serviceProviders: [CallHandlerProvider]
    ) {
      self.eventLoopGroup = eventLoopGroup
      self.target = target
      self.serviceProvidersByName = Dictionary(uniqueKeysWithValues: serviceProviders.map {
        ($0.serviceName, $0)
      })
    }

    /// Make a new configuration using default values.
    ///
    /// - Parameters:
    ///   - target: The target to bind to.
    ///   - eventLoopGroup: The `EventLoopGroup` the server should run on.
    ///   - serviceProviders: An array of `CallHandlerProvider`s which the server should use
    ///       to handle requests.
    /// - Returns: A configuration with default values set.
    public static func `default`(
      target: BindTarget,
      eventLoopGroup: EventLoopGroup,
      serviceProviders: [CallHandlerProvider]
    ) -> Configuration {
      return .init(
        eventLoopGroup: eventLoopGroup,
        target: target,
        serviceProviders: serviceProviders
      )
    }
  }
}

extension Server.Configuration {
  public struct CORS: Hashable, Sendable {
    /// Determines which 'origin' header field values are permitted in a CORS request.
    public var allowedOrigins: AllowedOrigins
    /// Sets the headers which are permitted in a response to a CORS request.
    public var allowedHeaders: [String]
    /// Enabling this value allows sets the "access-control-allow-credentials" header field
    /// to "true" in respones to CORS requests. This must be enabled if the client intends to send
    /// credentials.
    public var allowCredentialedRequests: Bool
    /// The maximum age in seconds which pre-flight CORS requests may be cached for.
    public var preflightCacheExpiration: Int

    public init(
      allowedOrigins: AllowedOrigins = .all,
      allowedHeaders: [String] = ["content-type", "x-grpc-web", "x-user-agent"],
      allowCredentialedRequests: Bool = false,
      preflightCacheExpiration: Int = 86400
    ) {
      self.allowedOrigins = allowedOrigins
      self.allowedHeaders = allowedHeaders
      self.allowCredentialedRequests = allowCredentialedRequests
      self.preflightCacheExpiration = preflightCacheExpiration
    }
  }
}

extension Server.Configuration.CORS {
  public struct AllowedOrigins: Hashable, Sendable {
    enum Wrapped: Hashable, Sendable {
      case all
      case only([String])
    }

    private(set) var wrapped: Wrapped
    private init(_ wrapped: Wrapped) {
      self.wrapped = wrapped
    }

    /// Allow all origin values.
    public static let all = Self(.all)

    /// Allow only the given origin values.
    public static func only(_ allowed: [String]) -> Self {
      return Self(.only(allowed))
    }
  }
}

extension ServerBootstrapProtocol {
  fileprivate func bind(to target: BindTarget) -> EventLoopFuture<Channel> {
    switch target.wrapped {
    case let .hostAndPort(host, port):
      return self.bind(host: host, port: port)

    case let .unixDomainSocket(path):
      return self.bind(unixDomainSocketPath: path)

    case let .socketAddress(address):
      return self.bind(to: address)

    case let .connectedSocket(socket):
      return self.withBoundSocket(socket)
    }
  }
}

extension Comparable {
  internal func clamped(to range: ClosedRange<Self>) -> Self {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}
