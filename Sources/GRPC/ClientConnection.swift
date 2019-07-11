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
public class ClientConnection {
  /// The channel which will handle gRPC calls.
  internal var channel: EventLoopFuture<Channel> {
    willSet {
      self.willSetChannel(to: newValue)
    }
    didSet {
      self.didSetChannel(to: self.channel)
    }
  }

  /// HTTP multiplexer from the `channel` handling gRPC calls.
  internal var multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

  /// The configuration for this client.
  internal let configuration: Configuration

  /// A monitor for the connectivity state.
  public let connectivity: ConnectivityStateMonitor

  /// Creates a new connection from the given configuration.
  public init(configuration: Configuration) {
    self.configuration = configuration
    self.connectivity = ConnectivityStateMonitor(delegate: configuration.connectivityStateDelegate)

    // We need to initialize `multiplexer` before we can call `willSetChannel` (which will then
    // assign `multiplexer` to one from the created `Channel`s pipeline).
    let eventLoop = configuration.eventLoopGroup.next()
    let unavailable = GRPCStatus(code: .unavailable, message: nil)
    self.multiplexer = eventLoop.makeFailedFuture(unavailable)

    self.channel = ClientConnection.makeChannel(
      configuration: self.configuration,
      connectivity: self.connectivity,
      backoffIterator: self.configuration.connectionBackoff?.makeIterator()
    )

    // `willSet` and `didSet` are called on initialization, so call them explicitly now.
    self.willSetChannel(to: channel)
    self.didSetChannel(to: channel)
  }

  /// The `EventLoop` this connection is using.
  public var eventLoop: EventLoop {
    return self.channel.eventLoop
  }

  /// Closes the connection to the server.
  public func close() -> EventLoopFuture<Void> {
    if self.connectivity.state == .shutdown {
      // We're already shutdown or in the process of shutting down.
      return channel.flatMap { $0.closeFuture }
    } else {
      self.connectivity.initiateUserShutdown()
      return channel.flatMap { $0.close() }
    }
  }
}

// MARK: - Channel creation

extension ClientConnection {
  /// Register a callback on the close future of the given `channel` to replace the channel (if
  /// possible) and also replace the `multiplexer` with that from the new channel.
  ///
  /// - Parameter channel: The channel that will be set.
  private func willSetChannel(to channel: EventLoopFuture<Channel>) {
    // If we're about to set the channel and the user has initiated a shutdown (i.e. while the new
    // channel was being created) then it is no longer needed.
    guard !self.connectivity.userHasInitiatedShutdown else {
      channel.whenSuccess { channel in
        channel.close(mode: .all, promise: nil)
      }
      return
    }

    channel.flatMap { $0.closeFuture }.whenComplete { _ in
      guard self.connectivity.canAttemptReconnect else { return }
      self.channel = ClientConnection.makeChannel(
        configuration: self.configuration,
        connectivity: self.connectivity,
        backoffIterator: self.configuration.connectionBackoff?.makeIterator()
      )
    }

    self.multiplexer = channel.flatMap {
      $0.pipeline.handler(type: HTTP2StreamMultiplexer.self)
    }
  }

  /// Register a callback on the given `channel` to update the connectivity state.
  ///
  /// - Parameter channel: The channel that was set.
  private func didSetChannel(to channel: EventLoopFuture<Channel>) {
    channel.whenComplete { result in
      switch result {
      case .success:
        self.connectivity.state = .ready

      case .failure:
        self.connectivity.state = .shutdown
      }
    }
  }

  /// Attempts to create a new `Channel` using the given configuration.
  ///
  /// This involves: creating a `ClientBootstrapProtocol`, connecting to a target and verifying that
  /// the TLS handshake was successful (if TLS was configured). We _may_ additiionally set a
  /// connection timeout and schedule a retry attempt (should the connection fail) if a
  /// `ConnectionBackoffIterator` is provided.
  ///
  /// - Parameter configuration: The configuration to start the connection with.
  /// - Parameter connectivity: A connectivity state monitor.
  /// - Parameter backoffIterator: An `Iterator` for `ConnectionBackoff` providing a sequence of
  ///     connection timeouts and backoff to use when attempting to create a connection.
  private class func makeChannel(
    configuration: Configuration,
    connectivity: ConnectivityStateMonitor,
    backoffIterator: ConnectionBackoffIterator?
  ) -> EventLoopFuture<Channel> {
    connectivity.state = .connecting
    let timeoutAndBackoff = backoffIterator?.next()

    let bootstrap = self.makeBootstrap(
      configuration: configuration,
      group: configuration.eventLoopGroup,
      timeout: timeoutAndBackoff?.timeout
    )

    let channel = bootstrap.connect(to: configuration.target).flatMap { channel -> EventLoopFuture<Channel> in
      if configuration.tlsConfiguration != nil {
        return channel.verifyTLS().map { channel }
      } else {
        return channel.eventLoop.makeSucceededFuture(channel)
      }
    }

    // If we don't have backoff then we can't retry, just return the `channel` no matter what
    // state we are in.
    guard let backoff = timeoutAndBackoff?.backoff else {
      return channel
    }

    // If our connection attempt was unsuccessful, schedule another attempt in some time.
    return channel.flatMapError { _ in
      // We will try to connect again: the failure is transient.
      connectivity.state = .transientFailure
      return ClientConnection.scheduleReconnectAttempt(
        in: backoff,
        on: channel.eventLoop,
        configuration: configuration,
        connectivity: connectivity,
        backoffIterator: backoffIterator
      )
    }
  }

  /// Schedule an attempt to make a channel in `timeout` seconds on the given `eventLoop`.
  private class func scheduleReconnectAttempt(
    in timeout: TimeInterval,
    on eventLoop: EventLoop,
    configuration: Configuration,
    connectivity: ConnectivityStateMonitor,
    backoffIterator: ConnectionBackoffIterator?
  ) -> EventLoopFuture<Channel> {
    // The `futureResult` of the scheduled task is of type
    // `EventLoopFuture<EventLoopFuture<Channel>>`, so we need to `flatMap` it to
    // remove a level of indirection.
    return eventLoop.scheduleTask(in: .seconds(timeInterval: timeout)) {
      ClientConnection.makeChannel(
        configuration: configuration,
        connectivity: connectivity,
        backoffIterator: backoffIterator
      )
    }.futureResult.flatMap { channel in
      channel
    }
  }

  /// Makes and configures a `ClientBootstrap` using the provided configuration.
  ///
  /// Enables `SO_REUSEADDR` and `TCP_NODELAY` and configures the `channelInitializer` to use the
  /// handlers detailed in the documentation for `ClientConnection`.
  ///
  /// - Parameter configuration: The configuration to prepare the bootstrap with.
  /// - Parameter group: The `EventLoopGroup` to use for the bootstrap.
  /// - Parameter timeout: The connection timeout in seconds. 
  private class func makeBootstrap(
    configuration: Configuration,
    group: EventLoopGroup,
    timeout: TimeInterval?
  ) -> ClientBootstrapProtocol {
    let bootstrap = GRPCNIO.makeClientBootstrap(group: group)
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

    if let timeout = timeout {
      return bootstrap.connectTimeout(.seconds(timeInterval: timeout))
    } else {
      return bootstrap
    }
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

    /// A delegate which is called when the connectivity state is changed.
    public var connectivityStateDelegate: ConnectivityStateDelegate?

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
    /// - Parameter connectivityStateDelegate: A connectivity state delegate, defaulting to `nil`.
    /// - Parameter tlsConfiguration: TLS configuration, defaulting to `nil`.
    /// - Parameter connectionBackoff: The connection backoff configuration to use, defaulting
    ///     to `nil`.
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = DebugOnlyLoggingClientErrorDelegate.shared,
      connectivityStateDelegate: ConnectivityStateDelegate? = nil,
      tlsConfiguration: TLSConfiguration? = nil,
      connectionBackoff: ConnectionBackoff? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.connectivityStateDelegate = connectivityStateDelegate
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

fileprivate extension ClientBootstrapProtocol {
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

      return self.pipeline.addHandlers(sslClientHandler, TLSVerificationHandler())
    } catch {
      return self.eventLoop.makeFailedFuture(error)
    }
  }

  /// Returns the `verification` future from the `TLSVerificationHandler` in this channels pipeline.
  func verifyTLS() -> EventLoopFuture<Void> {
    return self.pipeline.handler(type: TLSVerificationHandler.self).flatMap {
      $0.verification
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
