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
import Logging

/// Provides a single, managed connection to a server.
///
/// The connection to the server is provided by a single channel which will attempt to reconnect
/// to the server if the connection is dropped. This connection is guaranteed to always use the same
/// event loop.
///
/// The connection is initially setup with a handler to verify that TLS was established
/// successfully (assuming TLS is being used).
///
///               ┌──────────────────────────┐
///               │  DelegatingErrorHandler  │
///               └──────────▲───────────────┘
///                HTTP2Frame│
///               ┌──────────┴───────────────┐
///               │ SettingsObservingHandler │
///               └──────────▲───────────────┘
///                HTTP2Frame│
///                          │                ⠇ ⠇   ⠇ ⠇
///                          │               ┌┴─▼┐ ┌┴─▼┐
///                          │               │   | │   | HTTP/2 streams
///                          │               └▲─┬┘ └▲─┬┘
///                          │                │ │   │ │ HTTP2Frame
///                        ┌─┴────────────────┴─▼───┴─▼┐
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
/// handler removes itself from the pipeline once TLS has been verified. There is also a handler
/// after the multiplexer for observing the initial settings frame, after which it determines that
/// the connection state is `.ready` and removes itself from the channel. Finally there is a
/// delegated error handler which uses the error delegate associated with this connection
/// (see `DelegatingErrorHandler`).
///
/// See `BaseClientCall` for a description of the pipelines associated with each HTTP/2 stream.
public class ClientConnection {
  private let id: String
  private let logger: Logger

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

  internal let scheme: String
  internal let authority: String

  /// A monitor for the connectivity state.
  public let connectivity: ConnectivityStateMonitor

  /// The `EventLoop` this connection is using.
  public var eventLoop: EventLoop {
    return self.channel.eventLoop
  }

  /// Creates a new connection from the given configuration. Prefer using
  /// `ClientConnection.secure(group:)` to build a connection secured with TLS or
  /// `ClientConnection.insecure(group:)` to build a plaintext connection.
  ///
  /// - Important: Users should prefer using `ClientConnection.secure(group:)` to build a connection
  ///   with TLS, or `ClientConnection.insecure(group:)` to build a connection without TLS.
  public init(configuration: Configuration) {
    self.configuration = configuration
    self.scheme = configuration.tls == nil ? "http" : "https"
    self.authority = configuration.target.host

    let id = String(describing: UUID())
    self.id = id
    var logger = Logger(subsystem: .clientChannel)
    logger[metadataKey: MetadataKey.connectionID] = "\(id)"
    self.logger = logger

    self.connectivity = ConnectivityStateMonitor(
      delegate: configuration.connectivityStateDelegate,
      logger: logger
    )

    let eventLoop = configuration.eventLoopGroup.next()
    self.channel = ClientConnection.makeChannel(
      configuration: self.configuration,
      eventLoop: eventLoop,
      connectivity: self.connectivity,
      backoffIterator: configuration.connectionBackoff?.makeIterator(),
      logger: logger
    )

    self.multiplexer = self.channel.flatMap {
      $0.pipeline.handler(type: HTTP2StreamMultiplexer.self)
    }

    // `willSet` and `didSet` are *not* called on initialization, call them explicitly now.
    self.willSetChannel(to: self.channel)
    self.didSetChannel(to: self.channel)
  }

  /// Closes the connection to the server.
  public func close() -> EventLoopFuture<Void> {
    if self.connectivity.state == .shutdown {
      // We're already shutdown or in the process of shutting down.
      return self.channel.flatMap { $0.closeFuture }
    } else {
      self.connectivity.initiateUserShutdown()
      return self.channel.flatMap { $0.close() }
    }
  }
}

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
        self.logger.debug("user initiated shutdown during connection, closing channel")
        channel.close(mode: .all, promise: nil)
      }
      return
    }

    // If we get a channel and it closes then create a new one, if necessary.
    channel.flatMap { $0.closeFuture }.whenComplete { result in
      switch result {
      case .success:
        self.logger.debug("client connection shutdown successfully")
      case .failure(let error):
        self.logger.warning(
          "client connection shutdown failed",
          metadata: [MetadataKey.error: "\(error)"]
        )
      }

      guard self.connectivity.canAttemptReconnect else {
        return
      }

      // Something went wrong, but we'll try to fix it so let's update our state to reflect that.
      self.connectivity.state = .transientFailure

      self.logger.debug("client connection channel closed, creating a new one")
      self.channel = ClientConnection.makeChannel(
        configuration: self.configuration,
        eventLoop: channel.eventLoop,
        connectivity: self.connectivity,
        backoffIterator: self.configuration.connectionBackoff?.makeIterator(),
        logger: self.logger
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
    channel.whenFailure { _ in
      self.connectivity.state = .shutdown
    }
  }
}

// Note: documentation is inherited.
extension ClientConnection: GRPCChannel {
  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> where Request : GRPCPayload, Response : GRPCPayload {
    return UnaryCall(
      path: path,
      scheme: self.scheme,
      authority: self.authority,
      callOptions: callOptions,
      eventLoop: self.eventLoop,
      multiplexer: self.multiplexer,
      errorDelegate: self.configuration.errorDelegate,
      logger: self.logger,
      request: request
    )
  }

  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    return ClientStreamingCall(
      path: path,
      scheme: self.scheme,
      authority: self.authority,
      callOptions: callOptions,
      eventLoop: self.eventLoop,
      multiplexer: self.multiplexer,
      errorDelegate: self.configuration.errorDelegate,
      logger: self.logger
    )
  }

  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return ServerStreamingCall(
      path: path,
      scheme: self.scheme,
      authority: self.authority,
      callOptions: callOptions,
      eventLoop: self.eventLoop,
      multiplexer: self.multiplexer,
      errorDelegate: self.configuration.errorDelegate,
      logger: self.logger,
      request: request,
      handler: handler
    )
  }

  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return BidirectionalStreamingCall(
      path: path,
      scheme: self.scheme,
      authority: self.authority,
      callOptions: callOptions,
      eventLoop: self.eventLoop,
      multiplexer: self.multiplexer,
      errorDelegate: self.configuration.errorDelegate,
      logger: self.logger,
      handler: handler
    )
  }
}

extension ClientConnection {
  /// Attempts to create a new `Channel` using the given configuration.
  ///
  /// This involves: creating a `ClientBootstrapProtocol`, connecting to a target and verifying that
  /// the TLS handshake was successful (if TLS was configured). We _may_ additiionally set a
  /// connection timeout and schedule a retry attempt (should the connection fail) if a
  /// `ConnectionBackoffIterator` is provided.
  ///
  /// - Parameter configuration: The configuration to start the connection with.
  /// - Parameter eventLoop: The event loop to use for this connection.
  /// - Parameter connectivity: A connectivity state monitor.
  /// - Parameter backoffIterator: An `Iterator` for `ConnectionBackoff` providing a sequence of
  ///     connection timeouts and backoff to use when attempting to create a connection.
  private class func makeChannel(
    configuration: Configuration,
    eventLoop: EventLoop,
    connectivity: ConnectivityStateMonitor,
    backoffIterator: ConnectionBackoffIterator?,
    logger: Logger
  ) -> EventLoopFuture<Channel> {
    guard connectivity.state == .idle || connectivity.state == .transientFailure else {
      return configuration.eventLoopGroup.next().makeFailedFuture(GRPCStatus.processingError)
    }

    logger.debug("attempting to connect", metadata: ["target": "\(configuration.target)", "event_loop": "\(eventLoop)"])
    connectivity.state = .connecting
    let timeoutAndBackoff = backoffIterator?.next()

    let bootstrap = self.makeBootstrap(
      configuration: configuration,
      eventLoop: eventLoop,
      timeout: timeoutAndBackoff?.timeout,
      connectivityMonitor: connectivity,
      logger: logger
    )

    let channel = bootstrap.connect(to: configuration.target).flatMap { channel -> EventLoopFuture<Channel> in
      if configuration.tls != nil {
        return channel.verifyTLS().map { channel }
      } else {
        return channel.eventLoop.makeSucceededFuture(channel)
      }
    }

    // If we don't have backoff then we can't retry, just return the `channel` no matter what
    // state we are in.
    guard let backoff = timeoutAndBackoff?.backoff else {
      logger.debug("backoff exhausted, no more connection attempts will be made")
      return channel
    }

    // If our connection attempt was unsuccessful, schedule another attempt in some time.
    return channel.flatMapError { error in
      logger.notice("connection attempt failed", metadata: [MetadataKey.error: "\(error)"])
      // We will try to connect again: the failure is transient.
      connectivity.state = .transientFailure
      return ClientConnection.scheduleReconnectAttempt(
        in: backoff,
        on: channel.eventLoop,
        configuration: configuration,
        connectivity: connectivity,
        backoffIterator: backoffIterator,
        logger: logger
      )
    }
  }

  /// Schedule an attempt to make a channel in `timeout` seconds on the given `eventLoop`.
  private class func scheduleReconnectAttempt(
    in timeout: TimeInterval,
    on eventLoop: EventLoop,
    configuration: Configuration,
    connectivity: ConnectivityStateMonitor,
    backoffIterator: ConnectionBackoffIterator?,
    logger: Logger
  ) -> EventLoopFuture<Channel> {
    logger.debug("scheduling connection attempt", metadata: ["delay_seconds": "\(timeout)"])
    // The `futureResult` of the scheduled task is of type
    // `EventLoopFuture<EventLoopFuture<Channel>>`, so we need to `flatMap` it to
    // remove a level of indirection.
    return eventLoop.scheduleTask(in: .seconds(timeInterval: timeout)) {
      ClientConnection.makeChannel(
        configuration: configuration,
        eventLoop: eventLoop,
        connectivity: connectivity,
        backoffIterator: backoffIterator,
        logger: logger
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
  /// - Parameter eventLoop: The `EventLoop` to use for the bootstrap.
  /// - Parameter timeout: The connection timeout in seconds.
  /// - Parameter connectivityMonitor: The connectivity state monitor for the created channel.
  private class func makeBootstrap(
    configuration: Configuration,
    eventLoop: EventLoop,
    timeout: TimeInterval?,
    connectivityMonitor: ConnectivityStateMonitor,
    logger: Logger
  ) -> ClientBootstrapProtocol {
    // Provide a server hostname if we're using TLS. Prefer the override.
    var serverHostname: String? = configuration.tls.map {
      if let hostnameOverride = $0.hostnameOverride {
        logger.debug("using hostname override for TLS", metadata: ["server-hostname": "\(hostnameOverride)"])
        return hostnameOverride
      } else {
        let host = configuration.target.host
        logger.debug("using host from connection target for TLS", metadata: ["server-hostname": "\(host)"])
        return host
      }
    }
    
    if let hostname = serverHostname, hostname.isIPAddress {
      logger.debug("IP address cannot be used for TLS SNI extension. No host used", metadata: ["server-hostname": "\(hostname)"])
      serverHostname = nil
    }

    let bootstrap = PlatformSupport.makeClientBootstrap(group: eventLoop, logger: logger)
      // Enable SO_REUSEADDR and TCP_NODELAY.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
      .channelInitializer { channel in
        channel.configureGRPCClient(
          tlsConfiguration: configuration.tls?.configuration,
          tlsServerHostname: serverHostname,
          connectivityMonitor: connectivityMonitor,
          errorDelegate: configuration.errorDelegate,
          logger: logger
        )
      }

    if let timeout = timeout {
      logger.debug("setting connect timeout", metadata: ["timeout_seconds" : "\(timeout)"])
      return bootstrap.connectTimeout(.seconds(timeInterval: timeout))
    } else {
      logger.debug("no connect timeout provided")
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

  var host: String {
    switch self {
    case .hostAndPort(let host, _):
      return host
    case .socketAddress(.v4(let address)):
      return address.host
    case .socketAddress(.v6(let address)):
      return address.host
    case .unixDomainSocket, .socketAddress(.unixDomainSocket):
      return "localhost"
    }
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
    public var tls: TLS?

    /// The connection backoff configuration. If no connection retrying is required then this should
    /// be `nil`.
    public var connectionBackoff: ConnectionBackoff?

    /// The HTTP protocol used for this connection.
    public var httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol {
      return self.tls == nil ? .http : .https
    }

    /// Create a `Configuration` with some pre-defined defaults. Prefer using
    /// `ClientConnection.secure(group:)` to build a connection secured with TLS or
    /// `ClientConnection.insecure(group:)` to build a plaintext connection.
    ///
    /// - Parameter target: The target to connect to.
    /// - Parameter eventLoopGroup: The event loop group to run the connection on.
    /// - Parameter errorDelegate: The error delegate, defaulting to a delegate which will log only
    ///     on debug builds.
    /// - Parameter connectivityStateDelegate: A connectivity state delegate, defaulting to `nil`.
    /// - Parameter tlsConfiguration: TLS configuration, defaulting to `nil`.
    /// - Parameter connectionBackoff: The connection backoff configuration to use.
    /// - Parameter messageEncoding: Message compression configuration, defaults to no compression.
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = LoggingClientErrorDelegate(),
      connectivityStateDelegate: ConnectivityStateDelegate? = nil,
      tls: Configuration.TLS? = nil,
      connectionBackoff: ConnectionBackoff? = ConnectionBackoff()
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.connectivityStateDelegate = connectivityStateDelegate
      self.tls = tls
      self.connectionBackoff = connectionBackoff
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

extension Channel {
  /// Configure the channel with TLS.
  ///
  /// This function adds two handlers to the pipeline: the `NIOSSLClientHandler` to handle TLS, and
  /// the `TLSVerificationHandler` which verifies that a successful handshake was completed.
  ///
  /// - Parameter configuration: The configuration to configure the channel with.
  /// - Parameter serverHostname: The server hostname to use if the hostname should be verified.
  /// - Parameter errorDelegate: The error delegate to use for the TLS verification handler.
  func configureTLS(
    _ configuration: TLSConfiguration,
    serverHostname: String?,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    do {
      let sslClientHandler = try NIOSSLClientHandler(
        context: try NIOSSLContext(configuration: configuration),
        serverHostname: serverHostname
      )

      return self.pipeline.addHandlers(sslClientHandler, TLSVerificationHandler(logger: logger))
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

  func configureGRPCClient(
    tlsConfiguration: TLSConfiguration?,
    tlsServerHostname: String?,
    connectivityMonitor: ConnectivityStateMonitor,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    let tlsConfigured = tlsConfiguration.map {
      self.configureTLS($0, serverHostname: tlsServerHostname, errorDelegate: errorDelegate, logger: logger)
    }

    return (tlsConfigured ?? self.eventLoop.makeSucceededFuture(())).flatMap {
      self.configureHTTP2Pipeline(mode: .client)
    }.flatMap { _ in
      let settingsObserver = InitialSettingsObservingHandler(
        connectivityStateMonitor: connectivityMonitor,
        logger: logger
      )
      let errorHandler = DelegatingErrorHandler(
        logger: logger,
        delegate: errorDelegate
      )
      return self.pipeline.addHandlers(settingsObserver, errorHandler)
    }
  }

  func configureGRPCClient(
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    return self.configureHTTP2Pipeline(mode: .client).flatMap { _ in
      self.pipeline.addHandler(DelegatingErrorHandler(logger: logger, delegate: errorDelegate))
    }
  }
}

fileprivate extension TimeAmount {
  /// Creates a new `TimeAmount` from the given time interval in seconds.
  ///
  /// - Parameter timeInterval: The amount of time in seconds
  static func seconds(timeInterval: TimeInterval) -> TimeAmount {
    return .nanoseconds(Int64(timeInterval * 1_000_000_000))
  }
}

fileprivate extension String {
  var isIPAddress: Bool {
    // We need some scratch space to let inet_pton write into.
    var ipv4Addr = in_addr()
    var ipv6Addr = in6_addr()
    
    return self.withCString { ptr in
      return inet_pton(AF_INET, ptr, &ipv4Addr) == 1 ||
        inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
    }
  }
}
