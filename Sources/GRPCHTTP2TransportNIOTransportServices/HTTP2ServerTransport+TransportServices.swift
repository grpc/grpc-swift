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
  public final class TransportServices: ServerTransport, ListeningServerTransport {
    private let address: GRPCHTTP2Core.SocketAddress
    private let config: Config
    private let eventLoopGroup: NIOTSEventLoopGroup
    private let serverQuiescingHelper: ServerQuiescingHelper

    private enum State {
      case idle(EventLoopPromise<GRPCHTTP2Core.SocketAddress>)
      case listening(EventLoopFuture<GRPCHTTP2Core.SocketAddress>)
      case closedOrInvalidAddress(RuntimeError)

      var listeningAddressFuture: EventLoopFuture<GRPCHTTP2Core.SocketAddress> {
        get throws {
          switch self {
          case .idle(let eventLoopPromise):
            return eventLoopPromise.futureResult
          case .listening(let eventLoopFuture):
            return eventLoopFuture
          case .closedOrInvalidAddress(let runtimeError):
            throw runtimeError
          }
        }
      }

      enum OnBound {
        case succeedPromise(
          _ promise: EventLoopPromise<GRPCHTTP2Core.SocketAddress>,
          address: GRPCHTTP2Core.SocketAddress
        )
        case failPromise(
          _ promise: EventLoopPromise<GRPCHTTP2Core.SocketAddress>,
          error: RuntimeError
        )
      }

      mutating func addressBound(_ address: NIOCore.SocketAddress?) -> OnBound {
        switch self {
        case .idle(let listeningAddressPromise):
          if let address {
            self = .listening(listeningAddressPromise.futureResult)
            return .succeedPromise(
              listeningAddressPromise,
              address: GRPCHTTP2Core.SocketAddress(address)
            )

          } else {
            assertionFailure("Unknown address type")
            let invalidAddressError = RuntimeError(
              code: .transportError,
              message: "Unknown address type returned by transport."
            )
            self = .closedOrInvalidAddress(invalidAddressError)
            return .failPromise(listeningAddressPromise, error: invalidAddressError)
          }

        case .listening, .closedOrInvalidAddress:
          fatalError(
            "Invalid state: addressBound should only be called once and when in idle state"
          )
        }
      }

      enum OnClose {
        case failPromise(
          EventLoopPromise<GRPCHTTP2Core.SocketAddress>,
          error: RuntimeError
        )
        case doNothing
      }

      mutating func close() -> OnClose {
        let serverStoppedError = RuntimeError(
          code: .serverIsStopped,
          message: """
            There is no listening address bound for this server: there may have been \
            an error which caused the transport to close, or it may have shut down.
            """
        )

        switch self {
        case .idle(let listeningAddressPromise):
          self = .closedOrInvalidAddress(serverStoppedError)
          return .failPromise(listeningAddressPromise, error: serverStoppedError)

        case .listening:
          self = .closedOrInvalidAddress(serverStoppedError)
          return .doNothing

        case .closedOrInvalidAddress:
          return .doNothing
        }
      }
    }

    private let listeningAddressState: Mutex<State>

    /// The listening address for this server transport.
    ///
    /// It is an `async` property because it will only return once the address has been successfully bound.
    ///
    /// - Throws: A runtime error will be thrown if the address could not be bound or is not bound any
    /// longer, because the transport isn't listening anymore. It can also throw if the transport returned an
    /// invalid address.
    public var listeningAddress: GRPCHTTP2Core.SocketAddress {
      get async throws {
        try await self.listeningAddressState
          .withLock { try $0.listeningAddressFuture }
          .get()
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
      self.address = address
      self.config = config
      self.eventLoopGroup = eventLoopGroup
      self.serverQuiescingHelper = ServerQuiescingHelper(group: self.eventLoopGroup)

      let eventLoop = eventLoopGroup.any()
      self.listeningAddressState = Mutex(.idle(eventLoop.makePromise()))
    }

    public func listen(
      _ streamHandler: @escaping @Sendable (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      defer {
        switch self.listeningAddressState.withLock({ $0.close() }) {
        case .failPromise(let promise, let error):
          promise.fail(error)
        case .doNothing:
          ()
        }
      }

      let bootstrap: NIOTSListenerBootstrap

      let requireALPN: Bool
      let scheme: Scheme
      switch self.config.transportSecurity.wrapped {
      case .plaintext:
        requireALPN = false
        scheme = .http
        bootstrap = NIOTSListenerBootstrap(group: self.eventLoopGroup)

      case .tls(let tlsConfig):
        requireALPN = tlsConfig.requireALPN
        scheme = .https
        bootstrap = NIOTSListenerBootstrap(group: self.eventLoopGroup)
          .tlsOptions(try NWProtocolTLS.Options(tlsConfig))
      }

      let serverChannel =
        try await bootstrap
        .serverChannelOption(
          ChannelOptions.socketOption(.so_reuseaddr),
          value: 1
        )
        .serverChannelInitializer { channel in
          let quiescingHandler = self.serverQuiescingHelper.makeServerChannelHandler(
            channel: channel
          )
          return channel.pipeline.addHandler(quiescingHandler)
        }
        .bind(to: self.address) { channel in
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

      let action = self.listeningAddressState.withLock {
        $0.addressBound(serverChannel.channel.localAddress)
      }
      switch action {
      case .succeedPromise(let promise, let address):
        promise.succeed(address)
      case .failPromise(let promise, let error):
        promise.fail(error)
      }

      try await serverChannel.executeThenClose { inbound in
        try await withThrowingDiscardingTaskGroup { group in
          for try await (connectionChannel, streamMultiplexer) in inbound {
            group.addTask {
              try await self.handleConnection(
                connectionChannel,
                multiplexer: streamMultiplexer,
                streamHandler: streamHandler
              )
            }
          }
        }
      }
    }

    private func handleConnection(
      _ connection: NIOAsyncChannel<HTTP2Frame, HTTP2Frame>,
      multiplexer: ChannelPipeline.SynchronousOperations.HTTP2StreamMultiplexer,
      streamHandler: @escaping @Sendable (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      try await connection.executeThenClose { inbound, _ in
        await withDiscardingTaskGroup { group in
          group.addTask {
            do {
              for try await _ in inbound {}
            } catch {
              // We don't want to close the channel if one connection throws.
              return
            }
          }

          do {
            for try await (stream, descriptor) in multiplexer.inbound {
              group.addTask {
                await self.handleStream(stream, handler: streamHandler, descriptor: descriptor)
              }
            }
          } catch {
            return
          }
        }
      }
    }

    private func handleStream(
      _ stream: NIOAsyncChannel<RPCRequestPart, RPCResponsePart>,
      handler streamHandler: @escaping @Sendable (RPCStream<Inbound, Outbound>) async -> Void,
      descriptor: EventLoopFuture<MethodDescriptor>
    ) async {
      // It's okay to ignore these errors:
      // - If we get an error because the http2Stream failed to close, then there's nothing we can do
      // - If we get an error because the inner closure threw, then the only possible scenario in which
      // that could happen is if methodDescriptor.get() throws - in which case, it means we never got
      // the RPC metadata, which means we can't do anything either and it's okay to just kill the stream.
      try? await stream.executeThenClose { inbound, outbound in
        guard let descriptor = try? await descriptor.get() else {
          return
        }

        let rpcStream = RPCStream(
          descriptor: descriptor,
          inbound: RPCAsyncSequence(wrapping: inbound),
          outbound: RPCWriter.Closable(
            wrapping: ServerConnection.Stream.Outbound(
              responseWriter: outbound,
              http2Stream: stream
            )
          )
        )

        await streamHandler(rpcStream)
      }
    }

    public func beginGracefulShutdown() {
      self.serverQuiescingHelper.initiateShutdown(promise: nil)
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
