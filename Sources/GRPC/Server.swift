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
  /// Makes and configures a `ServerBootstrap` using the provided configuration.
  public class func makeBootstrap(configuration: Configuration) -> ServerBootstrapProtocol {
    let bootstrap = GRPCNIO.makeServerBootstrap(group: configuration.eventLoopGroup)

    // Backlog is only available on `ServerBootstrap`.
    if bootstrap is ServerBootstrap {
      // Specify a backlog to avoid overloading the server.
      _ = bootstrap.serverChannelOption(ChannelOptions.backlog, value: 256)
    }

    return bootstrap
      // Enable `SO_REUSEADDR` to avoid "address already in use" error.
      .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        let protocolSwitcher = HTTPProtocolSwitcher(errorDelegate: configuration.errorDelegate) { channel -> EventLoopFuture<Void> in
          let handlers: [ChannelHandler] = [
            HTTP1ToRawGRPCServerCodec(),
            GRPCChannelHandler(
              servicesByName: configuration.serviceProvidersByName,
              errorDelegate: configuration.errorDelegate
            )
          ]
          return channel.pipeline.addHandlers(handlers)
        }

        if let tls = configuration.tls {
          return channel.configureTLS(configuration: tls).flatMap {
            channel.pipeline.addHandler(protocolSwitcher)
          }
        } else {
          return channel.pipeline.addHandler(protocolSwitcher)
        }
      }

      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
  }

  /// Starts a server with the given configuration. See `Server.Configuration` for the options
  /// available to configure the server.
  public static func start(configuration: Configuration) -> EventLoopFuture<Server> {
    return makeBootstrap(configuration: configuration)
      .bind(to: configuration.target)
      .map { channel in
        Server(channel: channel, errorDelegate: configuration.errorDelegate)
      }
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

public typealias BindTarget = ConnectionTarget

extension Server {
  /// The configuration for a server.
  public struct Configuration {
    /// The target to bind to.
    public var target: BindTarget

    /// The event loop group to run the connection on.
    public var eventLoopGroup: EventLoopGroup

    /// Providers the server should use to handle gRPC requests.
    public var serviceProviders: [CallHandlerProvider]

    /// An error delegate which is called when errors are caught. Provided delegates **must not
    /// maintain a strong reference to this `Server`**. Doing so will cause a retain cycle.
    public var errorDelegate: ServerErrorDelegate?

    /// TLS configuration for this connection. `nil` if TLS is not desired.
    public var tls: TLS?

    /// Create a `Configuration` with some pre-defined defaults.
    ///
    /// - Parameter target: The target to bind to.
    /// - Parameter eventLoopGroup: The event loop group to run the server on.
    /// - Parameter serviceProviders: An array of `CallHandlerProvider`s which the server should use
    ///     to handle requests.
    /// - Parameter errorDelegate: The error delegate, defaulting to a logging delegate.
    /// - Parameter tlsConfiguration: TLS configuration, defaulting to `nil`.
    public init(
      target: BindTarget,
      eventLoopGroup: EventLoopGroup,
      serviceProviders: [CallHandlerProvider],
      errorDelegate: ServerErrorDelegate? = LoggingServerErrorDelegate.shared,
      tls: TLS? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.serviceProviders = serviceProviders
      self.errorDelegate = errorDelegate
      self.tls = tls
    }
  }

  /// The TLS configuration for a connection.
  public struct TLSConfiguration {
    /// The SSL context to use.
    public var sslContext: NIOSSLContext

    public init(sslContext: NIOSSLContext) {
      self.sslContext = sslContext
    }
  }
}

fileprivate extension Server.Configuration {
  var serviceProvidersByName: [String: CallHandlerProvider] {
    return Dictionary(uniqueKeysWithValues: self.serviceProviders.map { ($0.serviceName, $0) })
  }
}

fileprivate extension Channel {
  /// Configure an SSL handler on the channel.
  ///
  /// - Parameters:
  ///   - configuration: The configuration to use when creating the handler.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  func configureTLS(configuration: Server.Configuration.TLS) -> EventLoopFuture<Void> {
    do {
      let context = try NIOSSLContext(configuration: configuration.configuration)
      return self.pipeline.addHandler(try NIOSSLServerHandler(context: context))
    } catch {
      return self.pipeline.eventLoop.makeFailedFuture(error)
    }
  }
}

fileprivate extension ServerBootstrapProtocol {
  func bind(to target: BindTarget) -> EventLoopFuture<Channel> {
    switch target {
    case .hostAndPort(let host, let port):
      return self.bind(host: host, port: port)

    case .unixDomainSocket(let path):
      return self.bind(unixDomainSocketPath: path)

    case .socketAddress(let address):
      return self.bind(to: address)
    }
  }
}
