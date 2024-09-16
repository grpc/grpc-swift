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
internal import NIOCore
internal import NIOExtras
internal import NIOHTTP2
public import NIOPosix  // has to be public because of default argument value in init
private import Synchronization

#if canImport(NIOSSL)
import NIOSSL
#endif

extension HTTP2ServerTransport {
  /// A ``GRPCCore/ServerTransport`` using HTTP/2 built on top of `NIOPosix`.
  ///
  /// This transport builds on top of SwiftNIO's Posix networking layer and is suitable for use
  /// on Linux and Darwin based platform (macOS, iOS, etc.) However, it's *strongly* recommended
  /// that if you are targeting Darwin platforms then you should use the `NIOTS` variant of
  /// the ``GRPCHTTP2Core/HTTP2ServerTransport``.
  ///
  /// You can control various aspects of connection creation, management, security and RPC behavior via
  /// the ``Config``.
  ///
  /// Beyond creating the transport you don't need to interact with it directly, instead, pass it
  /// to a `GRPCServer`:
  ///
  /// ```swift
  /// try await withThrowingDiscardingTaskGroup { group in
  ///   let transport = HTTP2ServerTransport.Posix(
  ///     address: .ipv4(host: "127.0.0.1", port: 0),
  ///     config: .defaults(transportSecurity: .plaintext)
  ///   )
  ///   let server = GRPCServer(transport: transport, services: someServices)
  ///   group.addTask {
  ///     try await server.serve()
  ///   }
  ///
  ///   // ...
  /// }
  /// ```
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  public struct Posix: ServerTransport, ListeningServerTransport {
    private struct ListenerFactory: HTTP2ListenerFactory {
      let config: Config

      func makeListeningChannel(
        eventLoopGroup: any EventLoopGroup,
        address: GRPCHTTP2Core.SocketAddress,
        serverQuiescingHelper: ServerQuiescingHelper
      ) async throws -> NIOAsyncChannel<AcceptedChannel, Never> {
        #if canImport(NIOSSL)
        let sslContext: NIOSSLContext?

        switch self.config.transportSecurity.wrapped {
        case .plaintext:
          sslContext = nil
        case .tls(let tlsConfig):
          do {
            sslContext = try NIOSSLContext(configuration: TLSConfiguration(tlsConfig))
          } catch {
            throw RuntimeError(
              code: .transportError,
              message: "Couldn't create SSL context, check your TLS configuration.",
              cause: error
            )
          }
        }
        #endif

        let serverChannel = try await ServerBootstrap(group: eventLoopGroup)
          .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
          .serverChannelInitializer { channel in
            let quiescingHandler = serverQuiescingHelper.makeServerChannelHandler(channel: channel)
            return channel.pipeline.addHandler(quiescingHandler)
          }
          .bind(to: address) { channel in
            channel.eventLoop.makeCompletedFuture {
              #if canImport(NIOSSL)
              if let sslContext {
                try channel.pipeline.syncOperations.addHandler(
                  NIOSSLServerHandler(context: sslContext)
                )
              }
              #endif

              let requireALPN: Bool
              let scheme: Scheme
              switch self.config.transportSecurity.wrapped {
              case .plaintext:
                requireALPN = false
                scheme = .http
              case .tls(let tlsConfig):
                requireALPN = tlsConfig.requireALPN
                scheme = .https
              }

              return try channel.pipeline.syncOperations.configureGRPCServerPipeline(
                channel: channel,
                compressionConfig: self.config.compression,
                connectionConfig: self.config.connection,
                http2Config: self.config.http2,
                rpcConfig: self.config.rpc,
                requireALPN: requireALPN,
                scheme: scheme
              )
            }
          }

        return serverChannel
      }
    }

    private let underlyingTransport: CommonHTTP2ServerTransport<ListenerFactory>

    /// The listening address for this server transport.
    ///
    /// It is an `async` property because it will only return once the address has been successfully bound.
    ///
    /// - Throws: A runtime error will be thrown if the address could not be bound or is not bound any
    /// longer, because the transport isn't listening anymore. It can also throw if the transport returned an
    /// invalid address.
    public var listeningAddress: GRPCHTTP2Core.SocketAddress {
      get async throws {
        try await self.underlyingTransport.listeningAddress
      }
    }

    /// Create a new `Posix` transport.
    ///
    /// - Parameters:
    ///   - address: The address to which the server should be bound.
    ///   - config: The transport configuration.
    ///   - eventLoopGroup: The ELG from which to get ELs to run this transport.
    public init(
      address: GRPCHTTP2Core.SocketAddress,
      config: Config,
      eventLoopGroup: MultiThreadedEventLoopGroup = .singletonMultiThreadedEventLoopGroup
    ) {
      let factory = ListenerFactory(config: config)
      let helper = ServerQuiescingHelper(group: eventLoopGroup)
      self.underlyingTransport = CommonHTTP2ServerTransport(
        address: address,
        eventLoopGroup: eventLoopGroup,
        quiescingHelper: helper,
        listenerFactory: factory
      )
    }

    public func listen(
      _ streamHandler: @escaping @Sendable (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      try await self.underlyingTransport.listen(streamHandler)
    }

    public func beginGracefulShutdown() {
      self.underlyingTransport.beginGracefulShutdown()
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ServerTransport.Posix {
  /// Config for the `Posix` transport.
  public struct Config: Sendable {
    /// Compression configuration.
    public var compression: HTTP2ServerTransport.Config.Compression

    /// Connection configuration.
    public var connection: HTTP2ServerTransport.Config.Connection

    /// HTTP2 configuration.
    public var http2: HTTP2ServerTransport.Config.HTTP2

    /// RPC configuration.
    public var rpc: HTTP2ServerTransport.Config.RPC

    /// The transport's security.
    public var transportSecurity: TransportSecurity

    /// Construct a new `Config`.
    ///
    /// - Parameters:
    ///   - http2: HTTP2 configuration.
    ///   - rpc: RPC configuration.
    ///   - connection: Connection configuration.
    ///   - compression: Compression configuration.
    ///   - transportSecurity: The transport's security configuration.
    ///
    /// - SeeAlso: ``defaults(transportSecurity:configure:)``
    public init(
      http2: HTTP2ServerTransport.Config.HTTP2,
      rpc: HTTP2ServerTransport.Config.RPC,
      connection: HTTP2ServerTransport.Config.Connection,
      compression: HTTP2ServerTransport.Config.Compression,
      transportSecurity: TransportSecurity
    ) {
      self.compression = compression
      self.connection = connection
      self.http2 = http2
      self.rpc = rpc
      self.transportSecurity = transportSecurity
    }

    /// Default values for the different configurations.
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
        rpc: .defaults,
        connection: .defaults,
        compression: .defaults,
        transportSecurity: transportSecurity
      )
      configure(&config)
      return config
    }
  }
}

extension ServerBootstrap {
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  fileprivate func bind<Output: Sendable>(
    to address: GRPCHTTP2Core.SocketAddress,
    childChannelInitializer: @escaping @Sendable (any Channel) -> EventLoopFuture<Output>
  ) async throws -> NIOAsyncChannel<Output, Never> {
    if let virtualSocket = address.virtualSocket {
      return try await self.bind(
        to: VsockAddress(virtualSocket),
        childChannelInitializer: childChannelInitializer
      )
    } else {
      return try await self.bind(
        to: NIOCore.SocketAddress(address),
        childChannelInitializer: childChannelInitializer
      )
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension ServerTransport where Self == HTTP2ServerTransport.Posix {
  /// Create a new `Posix` based HTTP/2 server transport.
  ///
  /// - Parameters:
  ///   - address: The address to which the server should be bound.
  ///   - config: The transport configuration.
  ///   - eventLoopGroup: The underlying NIO `EventLoopGroup` to the server on. This must
  ///       be a `MultiThreadedEventLoopGroup` or an `EventLoop` from
  ///       a `MultiThreadedEventLoopGroup`.
  public static func http2NIOPosix(
    address: GRPCHTTP2Core.SocketAddress,
    config: HTTP2ServerTransport.Posix.Config,
    eventLoopGroup: MultiThreadedEventLoopGroup = .singletonMultiThreadedEventLoopGroup
  ) -> Self {
    return HTTP2ServerTransport.Posix(
      address: address,
      config: config,
      eventLoopGroup: eventLoopGroup
    )
  }
}
