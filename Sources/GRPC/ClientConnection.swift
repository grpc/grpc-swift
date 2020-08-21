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
import NIO
import NIOHTTP2
import NIOSSL
import NIOTLS
import NIOTransportServices
import SwiftProtobuf

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
  private let connectionManager: ConnectionManager

  private func getChannel() -> EventLoopFuture<Channel> {
    switch self.configuration.callStartBehavior.wrapped {
    case .waitsForConnectivity:
      return self.connectionManager.getChannel()

    case .fastFailure:
      return self.connectionManager.getOptimisticChannel()
    }
  }

  /// HTTP multiplexer from the `channel` handling gRPC calls.
  internal var multiplexer: EventLoopFuture<HTTP2StreamMultiplexer> {
    return self.getChannel().flatMap {
      $0.pipeline.handler(type: HTTP2StreamMultiplexer.self)
    }
  }

  /// The configuration for this client.
  internal let configuration: Configuration

  internal let scheme: String
  internal let authority: String

  /// A monitor for the connectivity state.
  public var connectivity: ConnectivityStateMonitor {
    return self.connectionManager.monitor
  }

  /// The `EventLoop` this connection is using.
  public var eventLoop: EventLoop {
    return self.connectionManager.eventLoop
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
    self.connectionManager = ConnectionManager(
      configuration: configuration,
      logger: configuration.backgroundActivityLogger
    )
  }

  /// Closes the connection to the server.
  public func close() -> EventLoopFuture<Void> {
    return self.connectionManager.shutdown()
  }

  /// Extracts a logger and request ID from the call options and returns them. The logger will
  /// be populated with the request ID (if applicable) and any metadata from the connection manager.
  private func populatedLoggerAndRequestID(from callOptions: CallOptions) -> (Logger, String?) {
    var logger = callOptions.logger
    self.connectionManager.appendMetadata(to: &logger)

    // Attach the request ID.
    let requestID = callOptions.requestIDProvider.requestID()
    if let requestID = requestID {
      logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
    }

    return (logger, requestID)
  }

  private func makeRequestHead(path: String, options: CallOptions,
                               requestID: String?) -> _GRPCRequestHead {
    return _GRPCRequestHead(
      scheme: self.scheme,
      path: path,
      host: self.authority,
      options: options,
      requestID: requestID
    )
  }
}

// MARK: - Unary

extension ClientConnection: GRPCChannel {
  private func makeUnaryCall<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    request: Serializer.Input,
    callOptions: CallOptions
  ) -> UnaryCall<Serializer.Input, Deserializer.Output> {
    let (logger, requestID) = self.populatedLoggerAndRequestID(from: callOptions)

    let call = UnaryCall<Serializer.Input, Deserializer.Output>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      serializer: serializer,
      deserializer: deserializer,
      callOptions: callOptions,
      errorDelegate: self.configuration.errorDelegate,
      logger: logger
    )

    call.send(
      self.makeRequestHead(path: path, options: callOptions, requestID: requestID),
      request: request
    )

    return call
  }

  /// A unary call using `SwiftProtobuf.Message` messages.
  public func makeUnaryCall<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> {
    return self.makeUnaryCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions
    )
  }

  /// A unary call using `GRPCPayload` messages.
  public func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> {
    return self.makeUnaryCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions
    )
  }
}

// MARK: - Client Streaming

extension ClientConnection {
  private func makeClientStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Serializer.Input, Deserializer.Output> {
    let (logger, requestID) = self.populatedLoggerAndRequestID(from: callOptions)

    let call = ClientStreamingCall<Serializer.Input, Deserializer.Output>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      serializer: serializer,
      deserializer: deserializer,
      callOptions: callOptions,
      errorDelegate: self.configuration.errorDelegate,
      logger: logger
    )

    call.sendHead(self.makeRequestHead(path: path, options: callOptions, requestID: requestID))

    return call
  }

  /// A client streaming call using `SwiftProtobuf.Message` messages.
  public func makeClientStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    return self.makeClientStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      callOptions: callOptions
    )
  }

  /// A client streaming call using `GRPCPayload` messages.
  public func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    return self.makeClientStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      callOptions: callOptions
    )
  }
}

// MARK: - Server Streaming

extension ClientConnection {
  private func makeServerStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    request: Serializer.Input,
    callOptions: CallOptions,
    handler: @escaping (Deserializer.Output) -> Void
  ) -> ServerStreamingCall<Serializer.Input, Deserializer.Output> {
    let (logger, requestID) = self.populatedLoggerAndRequestID(from: callOptions)

    let call = ServerStreamingCall<Serializer.Input, Deserializer.Output>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      serializer: serializer,
      deserializer: deserializer,
      callOptions: callOptions,
      errorDelegate: self.configuration.errorDelegate,
      logger: logger,
      responseHandler: handler
    )

    call.send(
      self.makeRequestHead(path: path, options: callOptions, requestID: requestID),
      request: request
    )

    return call
  }

  /// A server streaming call using `SwiftProtobuf.Message` messages.
  public func makeServerStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.makeServerStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }

  /// A server streaming call using `GRPCPayload` messages.
  public func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    return self.makeServerStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      request: request,
      callOptions: callOptions,
      handler: handler
    )
  }
}

// MARK: - Bidirectional Streaming

extension ClientConnection {
  private func makeBidirectionalStreamingCall<
    Serializer: MessageSerializer,
    Deserializer: MessageDeserializer
  >(
    serializer: Serializer,
    deserializer: Deserializer,
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Deserializer.Output) -> Void
  ) -> BidirectionalStreamingCall<Serializer.Input, Deserializer.Output> {
    let (logger, requestID) = self.populatedLoggerAndRequestID(from: callOptions)

    let call = BidirectionalStreamingCall<Serializer.Input, Deserializer.Output>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      serializer: serializer,
      deserializer: deserializer,
      callOptions: callOptions,
      errorDelegate: self.configuration.errorDelegate,
      logger: logger,
      responseHandler: handler
    )

    call.sendHead(self.makeRequestHead(path: path, options: callOptions, requestID: requestID))

    return call
  }

  /// A bidirectional streaming call using `SwiftProtobuf.Message` messages.
  public func makeBidirectionalStreamingCall<
    Request: SwiftProtobuf.Message,
    Response: SwiftProtobuf.Message
  >(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.makeBidirectionalStreamingCall(
      serializer: ProtobufSerializer(),
      deserializer: ProtobufDeserializer(),
      path: path,
      callOptions: callOptions,
      handler: handler
    )
  }

  /// A bidirectional streaming call using `GRPCPayload` messages.
  public func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.makeBidirectionalStreamingCall(
      serializer: GRPCPayloadSerializer(),
      deserializer: GRPCPayloadDeserializer(),
      path: path,
      callOptions: callOptions,
      handler: handler
    )
  }
}

// MARK: - Configuration structures

/// A target to connect to.
public struct ConnectionTarget {
  internal enum Wrapped {
    case hostAndPort(String, Int)
    case unixDomainSocket(String)
    case socketAddress(SocketAddress)
  }

  internal var wrapped: Wrapped
  private init(_ wrapped: Wrapped) {
    self.wrapped = wrapped
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

  var host: String {
    switch self.wrapped {
    case let .hostAndPort(host, _):
      return host
    case let .socketAddress(.v4(address)):
      return address.host
    case let .socketAddress(.v6(address)):
      return address.host
    case .unixDomainSocket, .socketAddress(.unixDomainSocket):
      return "localhost"
    }
  }
}

/// The connectivity behavior to use when starting an RPC.
public struct CallStartBehavior: Hashable {
  internal enum Behavior: Hashable {
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

    /// The `DispatchQueue` on which to call the connectivity state delegate. If a delegate is
    /// provided but the queue is `nil` then one will be created by gRPC.
    public var connectivityStateDelegateQueue: DispatchQueue?

    /// TLS configuration for this connection. `nil` if TLS is not desired.
    public var tls: TLS?

    /// The connection backoff configuration. If no connection retrying is required then this should
    /// be `nil`.
    public var connectionBackoff: ConnectionBackoff?

    /// The connection keepalive configuration.
    public var connectionKeepalive: ClientConnectionKeepalive

    /// The amount of time to wait before closing the connection. The idle timeout will start only
    /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start.
    ///
    /// If a connection becomes idle, starting a new RPC will automatically create a new connection.
    public var connectionIdleTimeout: TimeAmount

    /// The behavior used to determine when an RPC should start. That is, whether it should wait for
    /// an active connection or fail quickly if no connection is currently available.
    public var callStartBehavior: CallStartBehavior

    /// The HTTP/2 flow control target window size.
    public var httpTargetWindowSize: Int

    /// The HTTP protocol used for this connection.
    public var httpProtocol: HTTP2FramePayloadToHTTP1ClientCodec.HTTPProtocol {
      return self.tls == nil ? .http : .https
    }

    /// A logger for background information (such as connectivity state). A separate logger for
    /// requests may be provided in the `CallOptions`.
    ///
    /// Defaults to a no-op logger.
    public var backgroundActivityLogger: Logger

    /// A channel initializer which will be run after gRPC has initialized each channel. This may be
    /// used to add additional handlers to the pipeline and is intended for debugging.
    ///
    /// - Warning: The initializer closure may be invoked *multiple times*.
    public var debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)?

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
    /// - Parameter connectionIdleTimeout: The amount of time to wait before closing the connection, defaulting to 5 minutes.
    /// - Parameter callStartBehavior: The behavior used to determine when a call should start in
    ///     relation to its underlying connection. Defaults to `waitsForConnectivity`.
    /// - Parameter httpTargetWindowSize: The HTTP/2 flow control target window size.
    /// - Parameter backgroundActivityLogger: A logger for background information (such as
    ///     connectivity state). Defaults to a no-op logger.
    /// - Parameter debugChannelInitializer: A channel initializer will be called after gRPC has
    ///     initialized the channel. Defaults to `nil`.
    public init(
      target: ConnectionTarget,
      eventLoopGroup: EventLoopGroup,
      errorDelegate: ClientErrorDelegate? = LoggingClientErrorDelegate(),
      connectivityStateDelegate: ConnectivityStateDelegate? = nil,
      connectivityStateDelegateQueue: DispatchQueue? = nil,
      tls: Configuration.TLS? = nil,
      connectionBackoff: ConnectionBackoff? = ConnectionBackoff(),
      connectionKeepalive: ClientConnectionKeepalive = ClientConnectionKeepalive(),
      connectionIdleTimeout: TimeAmount = .minutes(5),
      callStartBehavior: CallStartBehavior = .waitsForConnectivity,
      httpTargetWindowSize: Int = 65535,
      backgroundActivityLogger: Logger = Logger(
        label: "io.grpc",
        factory: { _ in SwiftLogNoOpLogHandler() }
      ),
      debugChannelInitializer: ((Channel) -> EventLoopFuture<Void>)? = nil
    ) {
      self.target = target
      self.eventLoopGroup = eventLoopGroup
      self.errorDelegate = errorDelegate
      self.connectivityStateDelegate = connectivityStateDelegate
      self.connectivityStateDelegateQueue = connectivityStateDelegateQueue
      self.tls = tls
      self.connectionBackoff = connectionBackoff
      self.connectionKeepalive = connectionKeepalive
      self.connectionIdleTimeout = connectionIdleTimeout
      self.callStartBehavior = callStartBehavior
      self.httpTargetWindowSize = httpTargetWindowSize
      self.backgroundActivityLogger = backgroundActivityLogger
      self.debugChannelInitializer = debugChannelInitializer
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

  func configureGRPCClient(
    httpTargetWindowSize: Int,
    tlsConfiguration: TLSConfiguration?,
    tlsServerHostname: String?,
    connectionManager: ConnectionManager,
    connectionKeepalive: ClientConnectionKeepalive,
    connectionIdleTimeout: TimeAmount,
    errorDelegate: ClientErrorDelegate?,
    requiresZeroLengthWriteWorkaround: Bool,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    let tlsConfigured = tlsConfiguration.map {
      self.configureTLS(
        $0,
        serverHostname: tlsServerHostname,
        errorDelegate: errorDelegate,
        logger: logger
      )
    }

    let configuration: EventLoopFuture<Void> = (
      tlsConfigured ?? self.eventLoop
        .makeSucceededFuture(())
    ).flatMap {
      self.configureHTTP2Pipeline(
        mode: .client,
        targetWindowSize: httpTargetWindowSize,
        inboundStreamInitializer: nil
      )
    }.flatMap { _ in
      self.pipeline.handler(type: NIOHTTP2Handler.self).flatMap { http2Handler in
        self.pipeline.addHandlers(
          [
            GRPCClientKeepaliveHandler(configuration: connectionKeepalive),
            GRPCIdleHandler(
              mode: .client(connectionManager),
              logger: logger,
              idleTimeout: connectionIdleTimeout
            ),
          ],
          position: .after(http2Handler)
        )
      }.flatMap {
        let errorHandler = DelegatingErrorHandler(
          logger: logger,
          delegate: errorDelegate
        )
        return self.pipeline.addHandler(errorHandler)
      }
    }

    #if canImport(Network)
    // This availability guard is arguably unnecessary, but we add it anyway.
    if requiresZeroLengthWriteWorkaround, #available(
      OSX 10.14,
      iOS 12.0,
      tvOS 12.0,
      watchOS 6.0,
      *
    ) {
      return configuration.flatMap {
        self.pipeline.addHandler(NIOFilterEmptyWritesHandler(), position: .first)
      }
    } else {
      return configuration
    }
    #else
    return configuration
    #endif
  }

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
