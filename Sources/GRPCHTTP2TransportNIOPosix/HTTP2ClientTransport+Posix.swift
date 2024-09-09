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

public import GRPCCore
public import GRPCHTTP2Core  // should be @usableFromInline
public import NIOCore
public import NIOPosix  // has to be public because of default argument value in init

#if canImport(NIOSSL)
import NIOSSL
#endif

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport {
  /// A ``GRPCCore/ClientTransport`` using HTTP/2 built on top of `NIOPosix`.
  ///
  /// This transport builds on top of SwiftNIO's Posix networking layer and is suitable for use
  /// on Linux and Darwin based platform (macOS, iOS, etc.) However, it's *strongly* recommended
  /// that if you are targeting Darwin platforms then you should use the `NIOTS` variant of
  /// the ``GRPCHTTP2Core/HTTP2ClientTransport``.
  ///
  /// To use this transport you need to provide a 'target' to connect to which will be resolved
  /// by an appropriate resolver from the resolver registry. By default the resolver registry can
  /// resolve DNS targets, IPv4 and IPv6 targets, Unix domain socket targets, and Virtual Socket
  /// targets. If you use a custom target you must also provide an appropriately configured
  /// registry.
  ///
  /// You can control various aspects of connection creation, management, security and RPC behavior via
  /// the ``Config``. Load balancing policies and other RPC specific behavior can be configured via
  /// the ``ServiceConfig`` (if it isn't provided by a resolver).
  ///
  /// Beyond creating the transport you don't need to interact with it directly, instead, pass it
  /// to a `GRPCClient`:
  ///
  /// ```swift
  /// try await withThrowingDiscardingTaskGroup { group in
  ///   let transport = try HTTP2ClientTransport.Posix(
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
  public struct Posix: ClientTransport {
    private let channel: GRPCChannel

    /// Creates a new Posix based HTTP/2 client transport.
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
      eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup
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

      // Configure a connector.
      self.channel = GRPCChannel(
        resolver: resolver,
        connector: try Connector(eventLoopGroup: eventLoopGroup, config: config),
        config: GRPCChannel.Config(posix: config),
        defaultServiceConfig: serviceConfig
      )
    }

    public var retryThrottle: RetryThrottle? {
      self.channel.retryThrottle
    }

    public func connect() async {
      await self.channel.connect()
    }

    public func configuration(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
      self.channel.configuration(forMethod: descriptor)
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
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport.Posix {
  struct Connector: HTTP2Connector {
    private let config: HTTP2ClientTransport.Posix.Config
    private let eventLoopGroup: any EventLoopGroup

    #if canImport(NIOSSL)
    private let nioSSLContext: NIOSSLContext?
    private let serverHostname: String?
    #endif

    init(eventLoopGroup: any EventLoopGroup, config: HTTP2ClientTransport.Posix.Config) throws {
      self.eventLoopGroup = eventLoopGroup
      self.config = config

      #if canImport(NIOSSL)
      switch self.config.transportSecurity.wrapped {
      case .plaintext:
        self.nioSSLContext = nil
        self.serverHostname = nil
      case .tls(let tlsConfig):
        do {
          self.nioSSLContext = try NIOSSLContext(configuration: TLSConfiguration(tlsConfig))
          self.serverHostname = tlsConfig.serverHostname
        } catch {
          throw RuntimeError(
            code: .transportError,
            message: "Couldn't create SSL context, check your TLS configuration.",
            cause: error
          )
        }
      }
      #endif
    }

    func establishConnection(
      to address: GRPCHTTP2Core.SocketAddress
    ) async throws -> HTTP2Connection {
      let (channel, multiplexer) = try await ClientBootstrap(
        group: self.eventLoopGroup
      ).connect(to: address) { channel in
        channel.eventLoop.makeCompletedFuture {
          #if canImport(NIOSSL)
          if let nioSSLContext = self.nioSSLContext {
            try channel.pipeline.syncOperations.addHandler(
              NIOSSLClientHandler(
                context: nioSSLContext,
                serverHostname: self.serverHostname
              )
            )
          }
          #endif

          return try channel.pipeline.syncOperations.configureGRPCClientPipeline(
            channel: channel,
            config: GRPCChannel.Config(posix: self.config)
          )
        }
      }

      return HTTP2Connection(channel: channel, multiplexer: multiplexer, isPlaintext: true)
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ClientTransport.Posix {
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
    /// - SeeAlso: ``defaults(_:)``.
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
  init(posix: HTTP2ClientTransport.Posix.Config) {
    self.init(
      http2: posix.http2,
      backoff: posix.backoff,
      connection: posix.connection,
      compression: posix.compression
    )
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ClientTransport where Self == HTTP2ClientTransport.Posix {
  /// Creates a new Posix based HTTP/2 client transport.
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
  public static func http2NIOPosix(
    target: any ResolvableTarget,
    config: HTTP2ClientTransport.Posix.Config,
    resolverRegistry: NameResolverRegistry = .defaults,
    serviceConfig: ServiceConfig = ServiceConfig(),
    eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup
  ) throws -> Self {
    return try HTTP2ClientTransport.Posix(
      target: target,
      config: config,
      resolverRegistry: resolverRegistry,
      serviceConfig: serviceConfig,
      eventLoopGroup: eventLoopGroup
    )
  }
}
