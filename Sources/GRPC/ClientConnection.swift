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
#if os(Linux)
@preconcurrency import Foundation
#else
import Foundation
#endif

import Logging
import NIOCore
import NIOHPACK
import NIOHTTP2
import NIOPosix
#if canImport(NIOSSL)
import NIOSSL
#endif
import NIOTLS
import NIOTransportServices
import SwiftProtobuf

/// Provides a single, managed connection to a server which is guaranteed to always use the same
/// `EventLoop`.
///
/// The connection to the server is provided by a single channel which will attempt to reconnect to
/// the server if the connection is dropped. When either the client or server detects that the
/// connection has become idle -- that is, there are no outstanding RPCs and the idle timeout has
/// passed (5 minutes, by default) -- the underlying channel will be closed. The client will not
/// idle the connection if any RPC exists, even if there has been no activity on the RPC for the
/// idle timeout. Long-lived, low activity RPCs may benefit from configuring keepalive (see
/// ``ClientConnectionKeepalive``) which periodically pings the server to ensure that the connection
/// is not dropped. If the connection is idle a new channel will be created on-demand when the next
/// RPC is made.
///
/// The state of the connection can be observed using a ``ConnectivityStateDelegate``.
///
/// Since the connection is managed, and may potentially spend long periods of time waiting for a
/// connection to come up (cellular connections, for example), different behaviors may be used when
/// starting a call. The different behaviors are detailed in the ``CallStartBehavior`` documentation.
///
/// ### Channel Pipeline
///
/// The `NIO.ChannelPipeline` for the connection is configured as such:
///
///               ┌──────────────────────────┐
///               │  DelegatingErrorHandler  │
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
///                        │       GRPCIdleHandler     │
///                        └─▲───────────────────────┬─┘
///                HTTP2Frame│                       │HTTP2Frame
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOHTTP2Handler     │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOSSLHandler       │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                          │                       ▼
///
/// The 'GRPCIdleHandler' intercepts HTTP/2 frames and various events and is responsible for
/// informing and controlling the state of the connection (idling and keepalive). The HTTP/2 streams
/// are used to handle individual RPCs.
public final class ClientConnection: Sendable {
  private let connectionManager: ConnectionManager

  /// HTTP multiplexer from the underlying channel handling gRPC calls.
  internal func getMultiplexer() -> EventLoopFuture<HTTP2StreamMultiplexer> {
    return self.connectionManager.getHTTP2Multiplexer()
  }

  /// The configuration for this client.
  internal let configuration: Configuration

  /// The scheme of the URI for each RPC, i.e. 'http' or 'https'.
  internal let scheme: String

  /// The authority of the URI for each RPC.
  internal let authority: String

  /// A monitor for the connectivity state.
  public let connectivity: ConnectivityStateMonitor

  /// The `EventLoop` this connection is using.
  public var eventLoop: EventLoop {
    return self.connectionManager.eventLoop
  }

  /// Creates a new connection from the given configuration. Prefer using
  /// ``ClientConnection/secure(group:)`` to build a connection secured with TLS or
  /// ``ClientConnection/insecure(group:)`` to build a plaintext connection.
  ///
  /// - Important: Users should prefer using ``ClientConnection/secure(group:)`` to build a connection
  ///   with TLS, or ``ClientConnection/insecure(group:)`` to build a connection without TLS.
  public init(configuration: Configuration) {
    self.configuration = configuration
    self.scheme = configuration.tlsConfiguration == nil ? "http" : "https"
    self.authority = configuration.tlsConfiguration?.hostnameOverride ?? configuration.target.host

    let monitor = ConnectivityStateMonitor(
      delegate: configuration.connectivityStateDelegate,
      queue: configuration.connectivityStateDelegateQueue
    )

    self.connectivity = monitor
    self.connectionManager = ConnectionManager(
      configuration: configuration,
      connectivityDelegate: monitor,
      logger: configuration.backgroundActivityLogger
    )
  }

  /// Close the channel, and any connections associated with it. Any ongoing RPCs may fail.
  ///
  /// - Returns: Returns a future which will be resolved when shutdown has completed.
  public func close() -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.close(promise: promise)
    return promise.futureResult
  }

  /// Close the channel, and any connections associated with it. Any ongoing RPCs may fail.
  ///
  /// - Parameter promise: A promise which will be completed when shutdown has completed.
  public func close(promise: EventLoopPromise<Void>) {
    self.connectionManager.shutdown(mode: .forceful, promise: promise)
  }

  /// Attempt to gracefully shutdown the channel. New RPCs will be failed immediately and existing
  /// RPCs may continue to run until they complete.
  ///
  /// - Parameters:
  ///   - deadline: A point in time by which the graceful shutdown must have completed. If the
  ///       deadline passes and RPCs are still active then the connection will be closed forcefully
  ///       and any remaining in-flight RPCs may be failed.
  ///   - promise: A promise which will be completed when shutdown has completed.
  public func closeGracefully(deadline: NIODeadline, promise: EventLoopPromise<Void>) {
    return self.connectionManager.shutdown(mode: .graceful(deadline), promise: promise)
  }

  /// Populates the logger in `options` and appends a request ID header to the metadata, if
  /// configured.
  /// - Parameter options: The options containing the logger to populate.
  private func populateLogger(in options: inout CallOptions) {
    // Get connection metadata.
    self.connectionManager.appendMetadata(to: &options.logger)

    // Attach a request ID.
    let requestID = options.requestIDProvider.requestID()
    if let requestID = requestID {
      options.logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
      // Add the request ID header too.
      if let requestIDHeader = options.requestIDHeader {
        options.customMetadata.add(name: requestIDHeader, value: requestID)
      }
    }
  }
}

extension ClientConnection: GRPCChannel {
  public func makeCall<Request: Message, Response: Message>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    var options = callOptions
    self.populateLogger(in: &options)
    let multiplexer = self.getMultiplexer()
    let eventLoop = callOptions.eventLoopPreference.exact ?? multiplexer.eventLoop

    // This should be on the same event loop as the multiplexer (i.e. the event loop of the
    // underlying `Channel`.
    let channel = multiplexer.eventLoop.makePromise(of: Channel.self)
    multiplexer.whenComplete {
      ClientConnection.makeStreamChannel(using: $0, promise: channel)
    }

    return Call(
      path: path,
      type: type,
      eventLoop: eventLoop,
      options: options,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: channel.futureResult,
        authority: self.authority,
        scheme: self.scheme,
        maximumReceiveMessageLength: self.configuration.maximumReceiveMessageLength,
        errorDelegate: self.configuration.errorDelegate
      )
    )
  }

  public func makeCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    var options = callOptions
    self.populateLogger(in: &options)
    let multiplexer = self.getMultiplexer()
    let eventLoop = callOptions.eventLoopPreference.exact ?? multiplexer.eventLoop

    // This should be on the same event loop as the multiplexer (i.e. the event loop of the
    // underlying `Channel`.
    let channel = multiplexer.eventLoop.makePromise(of: Channel.self)
    multiplexer.whenComplete {
      ClientConnection.makeStreamChannel(using: $0, promise: channel)
    }

    return Call(
      path: path,
      type: type,
      eventLoop: eventLoop,
      options: options,
      interceptors: interceptors,
      transportFactory: .http2(
        channel: channel.futureResult,
        authority: self.authority,
        scheme: self.scheme,
        maximumReceiveMessageLength: self.configuration.maximumReceiveMessageLength,
        errorDelegate: self.configuration.errorDelegate
      )
    )
  }

  private static func makeStreamChannel(
    using result: Result<HTTP2StreamMultiplexer, Error>,
    promise: EventLoopPromise<Channel>
  ) {
    switch result {
    case let .success(multiplexer):
      multiplexer.createStreamChannel(promise: promise) {
        $0.eventLoop.makeSucceededVoidFuture()
      }
    case let .failure(error):
      promise.fail(error)
    }
  }
}

// MARK: - Configuration structures

/// A target to connect to.
public struct ConnectionTarget: Sendable {
  internal enum Wrapped {
    case hostAndPort(String, Int)
    case unixDomainSocket(String)
    case socketAddress(SocketAddress)
    case connectedSocket(NIOBSDSocket.Handle)
    case vsockAddress(VsockAddress)
  }

  internal var wrapped: Wrapped
  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
  }

  /// The host and port. The port is 443 by default.
  public static func host(_ host: String, port: Int = 443) -> ConnectionTarget {
    return ConnectionTarget(.hostAndPort(host, port))
  }

  /// The host and port.
  public static func hostAndPort(_ host: String, _ port: Int) -> ConnectionTarget {
    return ConnectionTarget(.hostAndPort(host, port))
  }

  /// The path of a Unix domain socket.
  public static func unixDomainSocket(_ path: String) -> ConnectionTarget {
    return ConnectionTarget(.unixDomainSocket(path))
  }

  /// A NIO socket address.
  public static func socketAddress(_ address: SocketAddress) -> ConnectionTarget {
    return ConnectionTarget(.socketAddress(address))
  }

  /// A connected NIO socket.
  public static func connectedSocket(_ socket: NIOBSDSocket.Handle) -> ConnectionTarget {
    return ConnectionTarget(.connectedSocket(socket))
  }

  /// A vsock socket.
  public static func vsockAddress(_ vsockAddress: VsockAddress) -> ConnectionTarget {
    return ConnectionTarget(.vsockAddress(vsockAddress))
  }

  @usableFromInline
  var host: String {
    switch self.wrapped {
    case let .hostAndPort(host, _):
      return host
    case let .socketAddress(.v4(address)):
      return address.host
    case let .socketAddress(.v6(address)):
      return address.host
    case .unixDomainSocket, .socketAddress(.unixDomainSocket), .connectedSocket:
      return "localhost"
    case let .vsockAddress(address):
      return "vsock://\(address.cid)"
    }
  }
}

/// The connectivity behavior to use when starting an RPC.
public struct CallStartBehavior: Hashable, Sendable {
  internal enum Behavior: Hashable, Sendable {
    case waitsForConnectivity
    case fastFailure
  }

  internal var wrapped: Behavior
  private init(_ wrapped: Behavior) {
    self.wrapped = wrapped
  }

  /// Waits for connectivity (that is, the 'ready' connectivity state) before attempting to start
  /// an RPC. Doing so may involve multiple connection attempts.
  ///
  /// This is the preferred, and default, behaviour.
  public static let waitsForConnectivity = CallStartBehavior(.waitsForConnectivity)

  /// The 'fast failure' behaviour is intended for cases where users would rather their RPC failed
  /// quickly rather than waiting for an active connection. The behaviour depends on the current
  /// connectivity state:
  ///
  /// - Idle: a connection attempt will be started and the RPC will fail if that attempt fails.
  /// - Connecting: a connection attempt is already in progress, the RPC will fail if that attempt
  ///     fails.
  /// - Ready: a connection is already active: the RPC will be started using that connection.
  /// - Transient failure: the last connection or connection attempt failed and gRPC is waiting to
  ///     connect again. The RPC will fail immediately.
  /// - Shutdown: the connection is shutdown, the RPC will fail immediately.
  public static let fastFailure = CallStartBehavior(.fastFailure)
}

extension ClientConnection {
  /// Configuration for a ``ClientConnection``. Users should prefer using one of the
  /// ``ClientConnection`` builders: ``ClientConnection/secure(group:)`` or ``ClientConnection/insecure(group:)``.
  public struct Configuration: Sendable {
    /// The target to connect to.
    public var target: ConnectionTarget

    /// The event loop group to run the connection on.
    public var eventLoopGroup: EventLoopGroup

    /// An error delegate which is called when errors are caught. Provided delegates **must not
    /// maintain a strong reference to this `ClientConnection`**. Doing so will cause a retain
    /// cycle. Defaults to ``LoggingClientErrorDelegate``.
    public var errorDelegate: ClientErrorDelegate? = LoggingClientErrorDelegate.shared

    /// A delegate which is called when the connectivity state is changed. Defaults to `nil`.
    public var connectivityStateDelegate: ConnectivityStateDelegate?

    /// The `DispatchQueue` on which to call the connectivity state delegate. If a delegate is
    /// provided but the queue is `nil` then one will be created by gRPC. Defaults to `nil`.
    public var connectivityStateDelegateQueue: DispatchQueue?

    #if canImport(NIOSSL)
    /// TLS configuration for this connection. `nil` if TLS is not desired.
    ///
    /// - Important: `tls` is deprecated; use ``tlsConfiguration`` or one of
    ///   the ``ClientConnection/usingTLS(with:on:)`` builder functions.
    @available(*, deprecated, renamed: "tlsConfiguration")
    public var tls: TLS? {
      get {
        return self.tlsConfiguration?.asDeprecatedClientConfiguration
      }
      set {
        self.tlsConfiguration = newValue.map { .init(transforming: $0) }
      }
    }
    #endif // canImport(NIOSSL)

    /// TLS configuration for this connection. `nil` if TLS is not desired.
    public var tlsConfiguration: GRPCTLSConfiguration?

    /// The connection backoff configuration. If no connection retrying is required then this should
    /// be `nil`.
    public var connectionBackoff: ConnectionBackoff? = ConnectionBackoff()

    /// The connection keepalive configuration.
    public var connectionKeepalive = ClientConnectionKeepalive()

    /// The amount of time to wait before closing the connection. The idle timeout will start only
    /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start.
    ///
    /// If a connection becomes idle, starting a new RPC will automatically create a new connection.
    ///
    /// Defaults to 30 minutes.
    public var connectionIdleTimeout: TimeAmount = .minutes(30)

    /// The behavior used to determine when an RPC should start. That is, whether it should wait for
    /// an active connection or fail quickly if no connection is currently available.
    ///
    /// Defaults to ``CallStartBehavior/waitsForConnectivity``.
    public var callStartBehavior: CallStartBehavior = .waitsForConnectivity

    /// The HTTP/2 flow control target window size. Defaults to 8MB. Values are clamped between
    /// 1 and 2^31-1 inclusive.
    public var httpTargetWindowSize = 8 * 1024 * 1024 {
      didSet {
        self.httpTargetWindowSize = self.httpTargetWindowSize.clamped(to: 1 ... Int(Int32.max))
      }
    }

    /// The HTTP/2 max frame size. Defaults to 16384. Value is clamped between 2^14 and 2^24-1
    /// octets inclusive (the minimum and maximum allowable values - HTTP/2 RFC 7540 4.2).
    public var httpMaxFrameSize: Int = 16384 {
      didSet {
        self.httpMaxFrameSize = self.httpMaxFrameSize.clamped(to: 16384 ... 16_777_215)
      }
    }

    /// The HTTP protocol used for this connection.
    public var httpProtocol: HTTP2FramePayloadToHTTP1ClientCodec.HTTPProtocol {
      return self.tlsConfiguration == nil ? .http : .https
    }

    /// The maximum size in bytes of a message which may be received from a server. Defaults to 4MB.
    public var maximumReceiveMessageLength: Int = 4 * 1024 * 1024 {
      willSet {
        precondition(newValue >= 0, "maximumReceiveMessageLength must be positive")
      }
    }

    /// A logger for background information (such as connectivity state). A separate logger for
    /// requests may be provided in the `CallOptions`.
    ///
    /// Defaults to a no-op logger.
    public var backgroundActivityLogger = Logger(
      label: "io.grpc",
      factory: { _ in SwiftLogNoOpLogHandler() }
    )

    /// A channel initializer which will be run after gRPC has initialized each channel. This may be
    /// used to add additional handlers to the pipeline and is intended for debugging.
    ///
    /// - Warning: The initializer closure may be invoked *multiple times*.
    @preconcurrency
    public var debugChannelInitializer: (@Sendable (Channel) -> EventLoopFuture<Void>)?

    #if canImport(NIOSSL)
    /// Create a `Configuration` with some pre-defined defaults. Prefer using
    /// `ClientConnection.secure(group:)` to build a connection secured with TLS or
    /// `ClientConnection.insecure(group:)` to build a plaintext connection.
    ///
    /// - Parameter target: The target to connect to.
    /// - Parameter eventLoopGroup: The event loop group to run the connection on.
    /// - Parameter errorDelegate: The error delegate, defaulting to a delegate which will log only
    ///     on debug builds.
    /// - Parameter connectivityStateDelegate: A connectivity state delegate, defaulting to `nil`.
    /// - Parameter connectivityStateDelegateQueue: A `DispatchQueue` on which to call the
    ///     `connectivityStateDelegate`.
    /// - Parameter tls: TLS configuration, defaulting to `nil`.
    /// - Parameter connectionBackoff: The connection backoff configuration to use.
    /// - Parameter connectionKeepalive: The keepalive configuration to use.
    /// - Parameter connectionIdleTimeout: The amount of time to wait before closing the connection, defaulting to 30 minutes.
    /// - Parameter callStartBehavior: The behavior used to determine when a call should start in
    ///     relation to its underlying connection. Defaults to `waitsForConnectivity`.
    /// - Parameter httpTargetWindowSize: The HTTP/2 flow control target window size.
    /// - Parameter backgroundActivityLogger: A logger for background information (such as
    ///     connectivity state). Defaults to a no-op logger.
    /// - Parameter debugChannelInitializer: A channel initializer will be called after gRPC has
    ///     initialized the channel. Defaults to `nil`.
    @available(*, deprecated, renamed: "default(target:eventLoopGroup:)")
    @preconcurrency
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = LoggingClientErrorDelegate(),
      connectivityStateDelegate: ConnectivityStateDelegate? = nil,
      connectivityStateDelegateQueue: DispatchQueue? = nil,
      tls: Configuration.TLS? = nil,
      connectionBackoff: ConnectionBackoff? = ConnectionBackoff(),
      connectionKeepalive: ClientConnectionKeepalive = ClientConnectionKeepalive(),
      connectionIdleTimeout: TimeAmount = .minutes(30),
      callStartBehavior: CallStartBehavior = .waitsForConnectivity,
      httpTargetWindowSize: Int = 8 * 1024 * 1024,
      backgroundActivityLogger: Logger = Logger(
        label: "io.grpc",
        factory: { _ in SwiftLogNoOpLogHandler() }
      ),
      debugChannelInitializer: (@Sendable (Channel) -> EventLoopFuture<Void>)? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.connectivityStateDelegate = connectivityStateDelegate
      self.connectivityStateDelegateQueue = connectivityStateDelegateQueue
      self.tlsConfiguration = tls.map { GRPCTLSConfiguration(transforming: $0) }
      self.connectionBackoff = connectionBackoff
      self.connectionKeepalive = connectionKeepalive
      self.connectionIdleTimeout = connectionIdleTimeout
      self.callStartBehavior = callStartBehavior
      self.httpTargetWindowSize = httpTargetWindowSize
      self.backgroundActivityLogger = backgroundActivityLogger
      self.debugChannelInitializer = debugChannelInitializer
    }
    #endif // canImport(NIOSSL)

    private init(eventLoopGroup: EventLoopGroup, target: ConnectionTarget) {
      self.eventLoopGroup = eventLoopGroup
      self.target = target
    }

    /// Make a new configuration using default values.
    ///
    /// - Parameters:
    ///   - target: The target to connect to.
    ///   - eventLoopGroup: The `EventLoopGroup` providing an `EventLoop` for the connection to
    ///       run on.
    /// - Returns: A configuration with default values set.
    public static func `default`(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup
    ) -> Configuration {
      return .init(eventLoopGroup: eventLoopGroup, target: target)
    }
  }
}

// MARK: - Configuration helpers/extensions

extension ClientBootstrapProtocol {
  /// Connect to the given connection target.
  ///
  /// - Parameter target: The target to connect to.
  func connect(to target: ConnectionTarget) -> EventLoopFuture<Channel> {
    switch target.wrapped {
    case let .hostAndPort(host, port):
      return self.connect(host: host, port: port)

    case let .unixDomainSocket(path):
      return self.connect(unixDomainSocketPath: path)

    case let .socketAddress(address):
      return self.connect(to: address)
    case let .connectedSocket(socket):
      return self.withConnectedSocket(socket)
    case let .vsockAddress(address):
      return self.connect(to: address)
    }
  }
}

#if canImport(NIOSSL)
extension ChannelPipeline.SynchronousOperations {
  internal func configureNIOSSLForGRPCClient(
    sslContext: Result<NIOSSLContext, Error>,
    serverHostname: String?,
    customVerificationCallback: NIOSSLCustomVerificationCallback?,
    logger: Logger
  ) throws {
    let sslContext = try sslContext.get()
    let sslClientHandler: NIOSSLClientHandler

    if let customVerificationCallback = customVerificationCallback {
      sslClientHandler = try NIOSSLClientHandler(
        context: sslContext,
        serverHostname: serverHostname,
        customVerificationCallback: customVerificationCallback
      )
    } else {
      sslClientHandler = try NIOSSLClientHandler(
        context: sslContext,
        serverHostname: serverHostname
      )
    }

    try self.addHandler(sslClientHandler)
    try self.addHandler(TLSVerificationHandler(logger: logger))
  }
}
#endif // canImport(NIOSSL)

extension ChannelPipeline.SynchronousOperations {
  internal func configureHTTP2AndGRPCHandlersForGRPCClient(
    channel: Channel,
    connectionManager: ConnectionManager,
    connectionKeepalive: ClientConnectionKeepalive,
    connectionIdleTimeout: TimeAmount,
    httpTargetWindowSize: Int,
    httpMaxFrameSize: Int,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) throws {
    let initialSettings = [
      // As per the default settings for swift-nio-http2:
      HTTP2Setting(parameter: .maxHeaderListSize, value: HPACKDecoder.defaultMaxHeaderListSize),
      // We never expect (or allow) server initiated streams.
      HTTP2Setting(parameter: .maxConcurrentStreams, value: 0),
      // As configured by the user.
      HTTP2Setting(parameter: .maxFrameSize, value: httpMaxFrameSize),
      HTTP2Setting(parameter: .initialWindowSize, value: httpTargetWindowSize),
    ]

    // We could use 'configureHTTP2Pipeline' here, but we need to add a few handlers between the
    // two HTTP/2 handlers so we'll do it manually instead.
    try self.addHandler(NIOHTTP2Handler(mode: .client, initialSettings: initialSettings))

    let h2Multiplexer = HTTP2StreamMultiplexer(
      mode: .client,
      channel: channel,
      targetWindowSize: httpTargetWindowSize,
      inboundStreamInitializer: nil
    )

    // The multiplexer is passed through the idle handler so it is only reported on
    // successful channel activation - with happy eyeballs multiple pipelines can
    // be constructed so it's not safe to report just yet.
    try self.addHandler(GRPCIdleHandler(
      connectionManager: connectionManager,
      multiplexer: h2Multiplexer,
      idleTimeout: connectionIdleTimeout,
      keepalive: connectionKeepalive,
      logger: logger
    ))

    try self.addHandler(h2Multiplexer)
    try self.addHandler(DelegatingErrorHandler(logger: logger, delegate: errorDelegate))
  }
}

extension Channel {
  func configureGRPCClient(
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    return self.configureHTTP2Pipeline(mode: .client, inboundStreamInitializer: nil).flatMap { _ in
      self.pipeline.addHandler(DelegatingErrorHandler(logger: logger, delegate: errorDelegate))
    }
  }
}

extension TimeAmount {
  /// Creates a new `TimeAmount` from the given time interval in seconds.
  ///
  /// - Parameter timeInterval: The amount of time in seconds
  static func seconds(timeInterval: TimeInterval) -> TimeAmount {
    return .nanoseconds(Int64(timeInterval * 1_000_000_000))
  }
}

extension String {
  var isIPAddress: Bool {
    // We need some scratch space to let inet_pton write into.
    var ipv4Addr = in_addr()
    var ipv6Addr = in6_addr()

    return self.withCString { ptr in
      inet_pton(AF_INET, ptr, &ipv4Addr) == 1 ||
        inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
    }
  }
}
