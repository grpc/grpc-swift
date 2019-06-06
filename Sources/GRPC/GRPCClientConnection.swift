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
import NIOHTTP2
import NIOSSL
import NIOTLS

/// Underlying channel and HTTP/2 stream multiplexer.
///
/// Different service clients implementing `GRPCClient` may share an instance of this class.
///
/// The connection is initially setup with a handler to verify that TLS was established
/// successfully (assuming TLS is being used).
///
///                          ▲                       |
///                HTTP2Frame│                       │HTTP2Frame
///                        ┌─┴───────────────────────▼─┐
///                        │   HTTP2StreamMultiplexer  |
///                        └─▲───────────────────────┬─┘
///                HTTP2Frame│                       │HTTP2Frame
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOHTTP2Handler     │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │ GRPCTLSVerificationHandler│
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOSSLHandler       │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                          │                       ▼
///
/// The `GRPCTLSVerificationHandler` observes the outcome of the SSL handshake and determines
/// whether a `GRPCClientConnection` should be returned to the user. In either eventuality, the
/// handler removes itself from the pipeline once TLS has been verified. There is also a delegated
/// error handler after the `HTTPStreamMultiplexer` in the main channel which uses the error
/// delegate associated with this connection (see `GRPCDelegatingErrorHandler`).
///
/// See `BaseClientCall` for a description of the remainder of the client pipeline.
open class GRPCClientConnection {
  /// Makes and configures a `ClientBootstrap` using the provided configuration.
  ///
  /// Enables `SO_REUSEADDR` and `TCP_NODELAY` and configures the `channelInitializer` to use the
  /// handlers detailed in the documentation for `GRPCClientConnection`.
  ///
  /// - Parameter configuration: The configuration to prepare the bootstrap with.
  public class func makeBootstrap(configuration: Configuration) -> ClientBootstrap {
    let bootstrap = ClientBootstrap(group: configuration.eventLoopGroup)
      // Enable SO_REUSEADDR and TCP_NODELAY.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        let tlsConfigured = configuration.tlsConfiguration.map { tlsConfiguration in
          channel.configureTLS(tlsConfiguration, errorDelegate: configuration.errorDelegate)
        }

        return (tlsConfigured ?? channel.eventLoop.makeSucceededFuture(())).flatMap {
          channel.configureHTTP2Pipeline(mode: .client)
        }.flatMap { _ in
          let errorHandler = GRPCDelegatingErrorHandler(delegate: configuration.errorDelegate)
          return channel.pipeline.addHandler(errorHandler)
        }
      }

    return bootstrap
  }

  /// Verifies that a TLS handshake was successful by using the `GRPCTLSVerificationHandler`.
  ///
  /// - Parameter channel: The channel to verify successful TLS setup on.
  public class func verifyTLS(channel: Channel) -> EventLoopFuture<Void> {
    return channel.pipeline.handler(type: GRPCTLSVerificationHandler.self).flatMap {
      $0.verification
    }
  }

  /// Makes a `GRPCClientConnection` from the given channel and configuration.
  ///
  /// - Parameter channel: The channel to use for the connection.
  /// - Parameter configuration: The configuration used to create the channel.
  public class func makeGRPCClientConnection(
    channel: Channel,
    configuration: Configuration
  ) -> EventLoopFuture<GRPCClientConnection> {
    return channel.pipeline.handler(type: HTTP2StreamMultiplexer.self).map { multiplexer in
      GRPCClientConnection(channel: channel, multiplexer: multiplexer, configuration: configuration)
    }
  }

  /// Starts a client connection using the given configuration.
  ///
  /// This involves: creating a `ClientBootstrap`, connecting to a target, verifying that the TLS
  /// handshake was successful (if TLS was configured) and creating the `GRPCClientConnection`.
  /// See the individual functions for more information:
  ///  - `makeBootstrap(configuration:)`,
  ///  - `verifyTLS(channel:)`, and
  ///  - `makeGRPCClientConnection(channel:configuration:)`.
  ///
  /// - Parameter configuration: The configuration to start the connection with.
  public class func start(_ configuration: Configuration) -> EventLoopFuture<GRPCClientConnection> {
    return makeBootstrap(configuration: configuration)
      .connect(to: configuration.target)
      .flatMap { channel in
        let tlsVerified: EventLoopFuture<Void>?
        if configuration.tlsConfiguration != nil {
          tlsVerified = verifyTLS(channel: channel)
        } else {
          tlsVerified = nil
        }

        return (tlsVerified ?? channel.eventLoop.makeSucceededFuture(())).flatMap {
          makeGRPCClientConnection(channel: channel, configuration: configuration)
        }
      }
  }

  public let channel: Channel
  public let multiplexer: HTTP2StreamMultiplexer
  public let configuration: Configuration

  init(channel: Channel, multiplexer: HTTP2StreamMultiplexer, configuration: Configuration) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.configuration = configuration
  }

  /// Fired when the client shuts down.
  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}

// MARK: - Configuration structures

/// A target to connect to.
public enum ConnectionTarget {
  /// The host and port.
  case hostAndPort(String, Int)
  /// The path of a Unix domain socket.
  case unixDomainSocket(String)
  /// A NIO socket address.
  case socketAddress(SocketAddress)

  var host: String? {
    guard case .hostAndPort(let host, _) = self else {
      return nil
    }
    return host
  }
}

extension GRPCClientConnection {
  /// The configuration for a connection.
  public struct Configuration {
    /// The target to connect to.
    public var target: ConnectionTarget

    /// The event loop group to run the connection on.
    public var eventLoopGroup: EventLoopGroup

    /// An error delegate which is called when errors are caught. Provided delegates **must not
    /// maintain a strong reference to this `GRPCClientConnection`**. Doing so will cause a retain
    /// cycle.
    public var errorDelegate: ClientErrorDelegate?

    /// TLS configuration for this connection. `nil` if TLS is not desired.
    public var tlsConfiguration: TLSConfiguration?

    /// The HTTP protocol used for this connection.
    public var httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol {
      return self.tlsConfiguration == nil ? .http : .https
    }

    /// Create a `Configuration` with some pre-defined defaults.
    ///
    /// - Parameter target: The target to connect to.
    /// - Parameter eventLoopGroup: The event loop group to run the connection on.
    /// - Parameter errorDelegate: The error delegate, defaulting to a delegate which will log only
    ///     on debug builds.
    /// - Parameter tlsConfiguration: TLS configuration, defaulting to `nil`.
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = DebugOnlyLoggingClientErrorDelegate.shared,
      tlsConfiguration: TLSConfiguration? = nil
      ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.tlsConfiguration = tlsConfiguration
    }
  }

  /// The TLS configuration for a connection.
  public struct TLSConfiguration {
    /// The SSL context to use.
    public var sslContext: NIOSSLContext
    /// Value to use for TLS SNI extension; this must not be an IP address.
    public var hostnameOverride: String?

    public init(sslContext: NIOSSLContext, hostnameOverride: String? = nil) {
      self.sslContext = sslContext
      self.hostnameOverride = hostnameOverride
    }
  }
}

// MARK: - Configuration helpers/extensions

fileprivate extension ClientBootstrap {
  /// Connect to the given connection target.
  ///
  /// - Parameter target: The target to connect to.
  func connect(to target: ConnectionTarget) -> EventLoopFuture<Channel> {
    switch target {
    case .hostAndPort(let host, let port):
      return self.connect(host: host, port: port)

    case .unixDomainSocket(let path):
      return self.connect(unixDomainSocketPath: path)

    case .socketAddress(let address):
      return self.connect(to: address)
    }
  }
}

fileprivate extension Channel {
  /// Configure the channel with TLS.
  ///
  /// This function adds two handlers to the pipeline: the `NIOSSLClientHandler` to handle TLS, and
  /// the `GRPCTLSVerificationHandler` which verifies that a successful handshake was completed.
  ///
  /// - Parameter configuration: The configuration to configure the channel with.
  /// - Parameter errorDelegate: The error delegate to use for the TLS verification handler.
  func configureTLS(
    _ configuration: GRPCClientConnection.TLSConfiguration,
    errorDelegate: ClientErrorDelegate?
    ) -> EventLoopFuture<Void> {
    do {
      let sslClientHandler = try NIOSSLClientHandler(
        context: configuration.sslContext,
        serverHostname: configuration.hostnameOverride)

      let verificationHandler = GRPCTLSVerificationHandler(errorDelegate: errorDelegate)
      return self.pipeline.addHandlers(sslClientHandler, verificationHandler)
    } catch {
      return self.eventLoop.makeFailedFuture(error)
    }
  }
}

// MARK: - Legacy APIs

extension GRPCClientConnection {
  /// Starts a connection to the given host and port.
  ///
  /// - Parameters:
  ///   - host: Host to connect to.
  ///   - port: Port on the host to connect to.
  ///   - eventLoopGroup: Event loop group to run the connection on.
  ///   - errorDelegate: An error delegate which is called when errors are caught. Provided
  ///       delegates **must not maintain a strong reference to this `GRPCClientConnection`**. Doing
  ///       so will cause a retain cycle. Defaults to a delegate which logs errors in debug builds
  ///       only.
  ///   - tlsMode: How TLS should be configured for this connection.
  ///   - hostOverride: Value to use for TLS SNI extension; this must not be an IP address. Ignored
  ///       if `tlsMode` is `.none`.
  /// - Returns: A future which will be fulfilled with a connection to the remote peer.
  public static func start(
    host: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    errorDelegate: ClientErrorDelegate? = DebugOnlyLoggingClientErrorDelegate.shared,
    tls tlsMode: TLSMode = .none,
    hostOverride: String? = nil
  ) throws -> EventLoopFuture<GRPCClientConnection> {
    var configuration = Configuration(
      target: .hostAndPort(host, port),
      eventLoopGroup: eventLoopGroup,
      errorDelegate: errorDelegate)

    if let sslContext = try tlsMode.makeSSLContext() {
      configuration.tlsConfiguration = .init(sslContext: sslContext, hostnameOverride: hostOverride)
    }

    return GRPCClientConnection.start(configuration)
  }

  public enum TLSMode {
    case none
    case anonymous
    case custom(NIOSSLContext)

    /// Returns an SSL context for the TLS mode.
    ///
    /// - Returns: An SSL context for the TLS mode, or `nil` if TLS is not being used.
    public func makeSSLContext() throws -> NIOSSLContext? {
      switch self {
      case .none:
        return nil

      case .anonymous:
        return try NIOSSLContext(configuration: .forClient())

      case .custom(let context):
        return context
      }
    }

    /// Rethrns the HTTP protocol for the TLS mode.
    public var httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol {
      switch self {
      case .none:
        return .http

      case .anonymous, .custom:
        return .https
      }
    }
  }
}
