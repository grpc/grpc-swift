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
///                        │   TLSVerificationHandler  │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOSSLHandler       │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                          │                       ▼
///
/// The `TLSVerificationHandler` observes the outcome of the SSL handshake and determines
/// whether a `ClientConnection` should be returned to the user. In either eventuality, the
/// handler removes itself from the pipeline once TLS has been verified. There is also a delegated
/// error handler after the `HTTPStreamMultiplexer` in the main channel which uses the error
/// delegate associated with this connection (see `DelegatingErrorHandler`).
///
/// See `BaseClientCall` for a description of the remainder of the client pipeline.
open class ClientConnection {
  /// Makes and configures a `ClientBootstrap` using the provided configuration.
  ///
  /// Enables `SO_REUSEADDR` and `TCP_NODELAY` and configures the `channelInitializer` to use the
  /// handlers detailed in the documentation for `ClientConnection`.
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
          let errorHandler = DelegatingErrorHandler(delegate: configuration.errorDelegate)
          return channel.pipeline.addHandler(errorHandler)
        }
      }

    return bootstrap
  }

  /// Verifies that a TLS handshake was successful by using the `TLSVerificationHandler`.
  ///
  /// - Parameter channel: The channel to verify successful TLS setup on.
  public class func verifyTLS(channel: Channel) -> EventLoopFuture<Void> {
    return channel.pipeline.handler(type: TLSVerificationHandler.self).flatMap {
      $0.verification
    }
  }

  /// Makes a `ClientConnection` from the given channel and configuration.
  ///
  /// - Parameter channel: The channel to use for the connection.
  /// - Parameter configuration: The configuration used to create the channel.
  public class func makeClientConnection(
    channel: Channel,
    configuration: Configuration
  ) -> EventLoopFuture<ClientConnection> {
    return channel.pipeline.handler(type: HTTP2StreamMultiplexer.self).map { multiplexer in
      ClientConnection(channel: channel, multiplexer: multiplexer, configuration: configuration)
    }
  }

  /// Starts a client connection using the given configuration.
  ///
  /// This involves: creating a `ClientBootstrap`, connecting to a target, verifying that the TLS
  /// handshake was successful (if TLS was configured) and creating the `ClientConnection`.
  /// See the individual functions for more information:
  ///  - `makeBootstrap(configuration:)`,
  ///  - `verifyTLS(channel:)`, and
  ///  - `makeClientConnection(channel:configuration:)`.
  ///
  /// - Parameter configuration: The configuration to start the connection with.
  public class func start(_ configuration: Configuration) -> EventLoopFuture<ClientConnection> {
    return start(configuration, backoffIterator: configuration.connectionBackoff?.makeIterator())
  }

  /// Starts a client connection using the given configuration and backoff.
  ///
  /// In addition to the steps taken in `start(configuration:)`, we _may_ additionally set a
  /// connection timeout and schedule a retry attempt (should the connection fail) if a
  /// `ConnectionBackoff.Iterator` is provided.
  ///
  /// - Parameter configuration: The configuration to start the connection with.
  /// - Parameter backoffIterator: A `ConnectionBackoff` iterator which generates connection
  ///     timeouts and backoffs to use when attempting to retry the connection.
  internal class func start(
    _ configuration: Configuration,
    backoffIterator: ConnectionBackoff.Iterator?
  ) -> EventLoopFuture<ClientConnection> {
    let timeoutAndBackoff = backoffIterator?.next()

    var bootstrap = makeBootstrap(configuration: configuration)
    // Set a timeout, if we have one.
    if let timeout = timeoutAndBackoff?.timeout {
      bootstrap = bootstrap.connectTimeout(.seconds(timeInterval: timeout))
    }

    let connection = bootstrap.connect(to: configuration.target)
      .flatMap { channel -> EventLoopFuture<ClientConnection> in
        let tlsVerified: EventLoopFuture<Void>?
        if configuration.tlsConfiguration != nil {
          tlsVerified = verifyTLS(channel: channel)
        } else {
          tlsVerified = nil
        }

        return (tlsVerified ?? channel.eventLoop.makeSucceededFuture(())).flatMap {
          makeClientConnection(channel: channel, configuration: configuration)
        }
      }

    guard let backoff = timeoutAndBackoff?.backoff else {
      return connection
    }

    // If we're in error then schedule our next attempt.
    return connection.flatMapError { error in
      // The `futureResult` of the scheduled task is of type
      // `EventLoopFuture<EventLoopFuture<ClientConnection>>`, so we need to `flatMap` it to
      // remove a level of indirection.
      return connection.eventLoop.scheduleTask(in: .seconds(timeInterval: backoff)) {
        return start(configuration, backoffIterator: backoffIterator)
      }.futureResult.flatMap { nextConnection in
        return nextConnection
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

extension ClientConnection {
  /// The configuration for a connection.
  public struct Configuration {
    /// The target to connect to.
    public var target: ConnectionTarget

    /// The event loop group to run the connection on.
    public var eventLoopGroup: EventLoopGroup

    /// An error delegate which is called when errors are caught. Provided delegates **must not
    /// maintain a strong reference to this `ClientConnection`**. Doing so will cause a retain
    /// cycle.
    public var errorDelegate: ClientErrorDelegate?

    /// TLS configuration for this connection. `nil` if TLS is not desired.
    public var tlsConfiguration: TLSConfiguration?

    /// The connection backoff configuration. If no connection retrying is required then this should
    /// be `nil`.
    public var connectionBackoff: ConnectionBackoff?

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
    /// - Parameter connectionBackoff: The connection backoff configuration to use, defaulting
    ///     to `nil`.
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = DebugOnlyLoggingClientErrorDelegate.shared,
      tlsConfiguration: TLSConfiguration? = nil,
      connectionBackoff: ConnectionBackoff? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.tlsConfiguration = tlsConfiguration
      self.connectionBackoff = connectionBackoff
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
  /// the `TLSVerificationHandler` which verifies that a successful handshake was completed.
  ///
  /// - Parameter configuration: The configuration to configure the channel with.
  /// - Parameter errorDelegate: The error delegate to use for the TLS verification handler.
  func configureTLS(
    _ configuration: ClientConnection.TLSConfiguration,
    errorDelegate: ClientErrorDelegate?
  ) -> EventLoopFuture<Void> {
    do {
      let sslClientHandler = try NIOSSLClientHandler(
        context: configuration.sslContext,
        serverHostname: configuration.hostnameOverride)

      let verificationHandler = TLSVerificationHandler(errorDelegate: errorDelegate)
      return self.pipeline.addHandlers(sslClientHandler, verificationHandler)
    } catch {
      return self.eventLoop.makeFailedFuture(error)
    }
  }
}

fileprivate extension TimeAmount {
  /// Creates a new `TimeAmount` from the given time interval in seconds.
  ///
  /// - Parameter timeInterval: The amount of time in seconds
  static func seconds(timeInterval: TimeInterval) -> TimeAmount {
    return .nanoseconds(TimeAmount.Value(timeInterval * 1_000_000_000))
  }
}
