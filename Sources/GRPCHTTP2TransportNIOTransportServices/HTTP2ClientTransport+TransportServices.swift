/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

#if canImport(Network)
public import GRPCCore
public import GRPCHTTP2Core
public import NIOTransportServices  // has to be public because of default argument value in init
public import NIOCore  // has to be public because of EventLoopGroup param in init

private import Network

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport {
  /// A `ClientTransport` using HTTP/2 built on top of `NIOTransportServices`.
  ///
  /// This transport builds on top of SwiftNIO's Transport Services networking layer and is the recommended
  /// variant for use on Darwin-based platforms (macOS, iOS, etc.).
  /// If you are targeting Linux platforms then you should use the `NIOPosix` variant of
  /// the `HTTP2ClientTransport`.
  ///
  /// To use this transport you need to provide a 'target' to connect to which will be resolved
  /// by an appropriate resolver from the resolver registry. By default the resolver registry can
  /// resolve DNS targets, IPv4 and IPv6 targets, and Unix domain socket targets. Virtual Socket
  /// targets are not supported with this transport. If you use a custom target you must also provide an
  /// appropriately configured registry.
  ///
  /// You can control various aspects of connection creation, management, security and RPC behavior via
  /// the ``Config``. Load balancing policies and other RPC specific behavior can be configured via
  /// the `ServiceConfig` (if it isn't provided by a resolver).
  ///
  /// Beyond creating the transport you don't need to interact with it directly, instead, pass it
  /// to a `GRPCClient`:
  ///
  /// ```swift
  /// try await withThrowingDiscardingTaskGroup { group in
  ///   let transport = try HTTP2ClientTransport.TransportServices(
  ///     target: .ipv4(host: "example.com"),
  ///     config: .defaults(transportSecurity: .plaintext)
  ///   )
  ///   let client = GRPCClient(transport: transport)
  ///   group.addTask {
  ///     try await client.run()
  ///   }
  ///
  ///   // ...
  /// }
  /// ```
  public struct TransportServices: ClientTransport {
    private let channel: GRPCChannel

    public var retryThrottle: RetryThrottle? {
      self.channel.retryThrottle
    }

    /// Creates a new NIOTransportServices-based HTTP/2 client transport.
    ///
    /// - Parameters:
    ///   - target: A target to resolve.
    ///   - config: Configuration for the transport.
    ///   - resolverRegistry: A registry of resolver factories.
    ///   - serviceConfig: Service config controlling how the transport should establish and
    ///       load-balance connections.
    ///   - eventLoopGroup: The underlying NIO `EventLoopGroup` to run connections on. This must
    ///       be a `MultiThreadedEventLoopGroup` or an `EventLoop` from
    ///       a `MultiThreadedEventLoopGroup`.
    /// - Throws: When no suitable resolver could be found for the `target`.
    public init(
      target: any ResolvableTarget,
      config: Config,
      resolverRegistry: NameResolverRegistry = .defaults,
      serviceConfig: ServiceConfig = ServiceConfig(),
      eventLoopGroup: any EventLoopGroup = .singletonNIOTSEventLoopGroup
    ) throws {
      guard let resolver = resolverRegistry.makeResolver(for: target) else {
        throw RuntimeError(
          code: .transportError,
          message: """
            No suitable resolvers to resolve '\(target)'. You must make sure that the resolver \
            registry has a suitable name resolver factory registered for the given target.
            """
        )
      }

      self.channel = GRPCChannel(
        resolver: resolver,
        connector: Connector(eventLoopGroup: eventLoopGroup, config: config),
        config: GRPCChannel.Config(transportServices: config),
        defaultServiceConfig: serviceConfig
      )
    }

    public func connect() async throws {
      await self.channel.connect()
    }

    public func beginGracefulShutdown() {
      self.channel.beginGracefulShutdown()
    }

    public func withStream<T: Sendable>(
      descriptor: MethodDescriptor,
      options: CallOptions,
      _ closure: (RPCStream<Inbound, Outbound>) async throws -> T
    ) async throws -> T {
      try await self.channel.withStream(descriptor: descriptor, options: options, closure)
    }

    public func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
      self.channel.config(forMethod: descriptor)
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport.TransportServices {
  struct Connector: HTTP2Connector {
    private let config: HTTP2ClientTransport.TransportServices.Config
    private let eventLoopGroup: any EventLoopGroup

    init(
      eventLoopGroup: any EventLoopGroup,
      config: HTTP2ClientTransport.TransportServices.Config
    ) {
      self.eventLoopGroup = eventLoopGroup
      self.config = config
    }

    func establishConnection(
      to address: GRPCHTTP2Core.SocketAddress
    ) async throws -> HTTP2Connection {
      let bootstrap: NIOTSConnectionBootstrap
      let isPlainText: Bool
      switch self.config.transportSecurity.wrapped {
      case .plaintext:
        isPlainText = true
        bootstrap = NIOTSConnectionBootstrap(group: self.eventLoopGroup)

      case .tls(let tlsConfig):
        isPlainText = false
        bootstrap = NIOTSConnectionBootstrap(group: self.eventLoopGroup)
          .tlsOptions(try NWProtocolTLS.Options(tlsConfig))
      }

      let (channel, multiplexer) = try await bootstrap.connect(to: address) { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureGRPCClientPipeline(
            channel: channel,
            config: GRPCChannel.Config(transportServices: self.config)
          )
        }
      }

      return HTTP2Connection(
        channel: channel,
        multiplexer: multiplexer,
        isPlaintext: isPlainText
      )
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport.TransportServices {
  /// Configuration for the `TransportServices` transport.
  public struct Config: Sendable {
    /// Configuration for HTTP/2 connections.
    public var http2: HTTP2ClientTransport.Config.HTTP2

    /// Configuration for backoff used when establishing a connection.
    public var backoff: HTTP2ClientTransport.Config.Backoff

    /// Configuration for connection management.
    public var connection: HTTP2ClientTransport.Config.Connection

    /// Compression configuration.
    public var compression: HTTP2ClientTransport.Config.Compression

    /// The transport's security.
    public var transportSecurity: TransportSecurity

    /// Creates a new connection configuration.
    ///
    /// - Parameters:
    ///   - http2: HTTP2 configuration.
    ///   - backoff: Backoff configuration.
    ///   - connection: Connection configuration.
    ///   - compression: Compression configuration.
    ///   - transportSecurity: The transport's security configuration.
    ///
    /// - SeeAlso: ``defaults(transportSecurity:configure:)``
    public init(
      http2: HTTP2ClientTransport.Config.HTTP2,
      backoff: HTTP2ClientTransport.Config.Backoff,
      connection: HTTP2ClientTransport.Config.Connection,
      compression: HTTP2ClientTransport.Config.Compression,
      transportSecurity: TransportSecurity
    ) {
      self.http2 = http2
      self.connection = connection
      self.backoff = backoff
      self.compression = compression
      self.transportSecurity = transportSecurity
    }

    /// Default values.
    ///
    /// - Parameters:
    ///   - transportSecurity: The security settings applied to the transport.
    ///   - configure: A closure which allows you to modify the defaults before returning them.
    public static func defaults(
      transportSecurity: TransportSecurity,
      configure: (_ config: inout Self) -> Void = { _ in }
    ) -> Self {
      var config = Self(
        http2: .defaults,
        backoff: .defaults,
        connection: .defaults,
        compression: .defaults,
        transportSecurity: transportSecurity
      )
      configure(&config)
      return config
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GRPCChannel.Config {
  init(transportServices config: HTTP2ClientTransport.TransportServices.Config) {
    self.init(
      http2: config.http2,
      backoff: config.backoff,
      connection: config.connection,
      compression: config.compression
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension NIOTSConnectionBootstrap {
  fileprivate func connect<Output: Sendable>(
    to address: GRPCHTTP2Core.SocketAddress,
    childChannelInitializer: @escaping @Sendable (any Channel) -> EventLoopFuture<Output>
  ) async throws -> Output {
    if address.virtualSocket != nil {
      throw RuntimeError(
        code: .transportError,
        message: """
            Virtual sockets are not supported by 'HTTP2ClientTransport.TransportServices'. \
            Please use the 'HTTP2ClientTransport.Posix' transport.
          """
      )
    } else {
      return try await self.connect(
        to: NIOCore.SocketAddress(address),
        channelInitializer: childChannelInitializer
      )
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientTransport where Self == HTTP2ClientTransport.TransportServices {
  /// Create a new `TransportServices` based HTTP/2 client transport.
  ///
  /// - Parameters:
  ///   - target: A target to resolve.
  ///   - config: Configuration for the transport.
  ///   - resolverRegistry: A registry of resolver factories.
  ///   - serviceConfig: Service config controlling how the transport should establish and
  ///       load-balance connections.
  ///   - eventLoopGroup: The underlying NIO `EventLoopGroup` to run connections on. This must
  ///       be a `NIOTSEventLoopGroup` or an `EventLoop` from
  ///       a `NIOTSEventLoopGroup`.
  /// - Throws: When no suitable resolver could be found for the `target`.
  public static func http2NIOTS(
    target: any ResolvableTarget,
    config: HTTP2ClientTransport.TransportServices.Config,
    resolverRegistry: NameResolverRegistry = .defaults,
    serviceConfig: ServiceConfig = ServiceConfig(),
    eventLoopGroup: any EventLoopGroup = .singletonNIOTSEventLoopGroup
  ) throws -> Self {
    try HTTP2ClientTransport.TransportServices(
      target: target,
      config: config,
      resolverRegistry: resolverRegistry,
      serviceConfig: serviceConfig,
      eventLoopGroup: eventLoopGroup
    )
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension NWProtocolTLS.Options {
  convenience init(_ tlsConfig: HTTP2ClientTransport.TransportServices.Config.TLS) throws {
    self.init()

    guard let sec_identity = sec_identity_create(try tlsConfig.identityProvider()) else {
      throw RuntimeError(
        code: .transportError,
        message: """
          There was an issue creating the SecIdentity required to set up TLS. \
          Please check your TLS configuration.
          """
      )
    }

    sec_protocol_options_set_local_identity(
      self.securityProtocolOptions,
      sec_identity
    )

    sec_protocol_options_set_min_tls_protocol_version(
      self.securityProtocolOptions,
      .TLSv12
    )

    for `protocol` in ["grpc-exp", "h2"] {
      sec_protocol_options_add_tls_application_protocol(
        self.securityProtocolOptions,
        `protocol`
      )
    }
  }
}
#endif
