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
public import NIOTransportServices  // has to be public because of default argument value in init
public import GRPCHTTP2Core

private import NIOCore
private import NIOExtras
private import NIOHTTP2
private import Network

private import Synchronization

extension HTTP2ServerTransport {
  /// A NIO Transport Services-backed implementation of a server transport.
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  public struct TransportServices: ServerTransport, ListeningServerTransport {
    private struct ListenerFactory: HTTP2ListenerFactory {
      let config: Config

      func makeListeningChannel(
        eventLoopGroup: any EventLoopGroup,
        address: GRPCHTTP2Core.SocketAddress,
        serverQuiescingHelper: ServerQuiescingHelper
      ) async throws -> NIOAsyncChannel<AcceptedChannel, Never> {
        let bootstrap: NIOTSListenerBootstrap

        let requireALPN: Bool
        let scheme: Scheme
        switch self.config.transportSecurity.wrapped {
        case .plaintext:
          requireALPN = false
          scheme = .http
          bootstrap = NIOTSListenerBootstrap(group: eventLoopGroup)

        case .tls(let tlsConfig):
          requireALPN = tlsConfig.requireALPN
          scheme = .https
          bootstrap = NIOTSListenerBootstrap(group: eventLoopGroup)
            .tlsOptions(try NWProtocolTLS.Options(tlsConfig))
        }

        let serverChannel =
          try await bootstrap
          .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
          .serverChannelInitializer { channel in
            let quiescingHandler = serverQuiescingHelper.makeServerChannelHandler(channel: channel)
            return channel.pipeline.addHandler(quiescingHandler)
          }
          .bind(to: address) { channel in
            channel.eventLoop.makeCompletedFuture {
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

    /// Create a new `TransportServices` transport.
    ///
    /// - Parameters:
    ///   - address: The address to which the server should be bound.
    ///   - config: The transport configuration.
    ///   - eventLoopGroup: The ELG from which to get ELs to run this transport.
    public init(
      address: GRPCHTTP2Core.SocketAddress,
      config: Config,
      eventLoopGroup: NIOTSEventLoopGroup = .singletonNIOTSEventLoopGroup
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
      streamHandler: @escaping @Sendable (
        _ stream: RPCStream<Inbound, Outbound>,
        _ context: ServerContext
      ) async -> Void
    ) async throws {
      try await self.underlyingTransport.listen(streamHandler: streamHandler)
    }

    public func beginGracefulShutdown() {
      self.underlyingTransport.beginGracefulShutdown()
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ServerTransport.TransportServices {
  /// Configuration for the `TransportServices` transport.
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
    /// - Parameters:
    ///   - compression: Compression configuration.
    ///   - connection: Connection configuration.
    ///   - http2: HTTP2 configuration.
    ///   - rpc: RPC configuration.
    ///   - transportSecurity: The transport's security configuration.
    public init(
      compression: HTTP2ServerTransport.Config.Compression,
      connection: HTTP2ServerTransport.Config.Connection,
      http2: HTTP2ServerTransport.Config.HTTP2,
      rpc: HTTP2ServerTransport.Config.RPC,
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
    ///   - transportSecurity: The transport's security configuration.
    ///   - configure: A closure which allows you to modify the defaults before returning them.
    public static func defaults(
      transportSecurity: TransportSecurity,
      configure: (_ config: inout Self) -> Void = { _ in }
    ) -> Self {
      var config = Self(
        compression: .defaults,
        connection: .defaults,
        http2: .defaults,
        rpc: .defaults,
        transportSecurity: transportSecurity
      )
      configure(&config)
      return config
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension NIOTSListenerBootstrap {
  fileprivate func bind<Output: Sendable>(
    to address: GRPCHTTP2Core.SocketAddress,
    childChannelInitializer: @escaping @Sendable (any Channel) -> EventLoopFuture<Output>
  ) async throws -> NIOAsyncChannel<Output, Never> {
    if address.virtualSocket != nil {
      throw RuntimeError(
        code: .transportError,
        message: """
            Virtual sockets are not supported by 'HTTP2ServerTransport.TransportServices'. \
            Please use the 'HTTP2ServerTransport.Posix' transport.
          """
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
extension ServerTransport where Self == HTTP2ServerTransport.TransportServices {
  /// Create a new `TransportServices` based HTTP/2 server transport.
  ///
  /// - Parameters:
  ///   - address: The address to which the server should be bound.
  ///   - config: The transport configuration.
  ///   - eventLoopGroup: The underlying NIO `EventLoopGroup` to the server on. This must
  ///       be a `NIOTSEventLoopGroup` or an `EventLoop` from a `NIOTSEventLoopGroup`.
  public static func http2NIOTS(
    address: GRPCHTTP2Core.SocketAddress,
    config: HTTP2ServerTransport.TransportServices.Config,
    eventLoopGroup: NIOTSEventLoopGroup = .singletonNIOTSEventLoopGroup
  ) -> Self {
    return HTTP2ServerTransport.TransportServices(
      address: address,
      config: config,
      eventLoopGroup: eventLoopGroup
    )
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension NWProtocolTLS.Options {
  convenience init(_ tlsConfig: HTTP2ServerTransport.TransportServices.Config.TLS) throws {
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
