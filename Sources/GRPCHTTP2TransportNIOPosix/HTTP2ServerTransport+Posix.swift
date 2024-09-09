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
  public final class Posix: ServerTransport, ListeningServerTransport {
    private let address: GRPCHTTP2Core.SocketAddress
    private let config: Config
    private let eventLoopGroup: MultiThreadedEventLoopGroup
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

      mutating func addressBound(
        _ address: NIOCore.SocketAddress?,
        userProvidedAddress: GRPCHTTP2Core.SocketAddress
      ) -> OnBound {
        switch self {
        case .idle(let listeningAddressPromise):
          if let address {
            self = .listening(listeningAddressPromise.futureResult)
            return .succeedPromise(
              listeningAddressPromise,
              address: GRPCHTTP2Core.SocketAddress(address)
            )

          } else if userProvidedAddress.virtualSocket != nil {
            self = .listening(listeningAddressPromise.futureResult)
            return .succeedPromise(listeningAddressPromise, address: userProvidedAddress)

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

      #if canImport(NIOSSL)
      let nioSSLContext: NIOSSLContext?
      switch self.config.transportSecurity.wrapped {
      case .plaintext:
        nioSSLContext = nil
      case .tls(let tlsConfig):
        do {
          nioSSLContext = try NIOSSLContext(configuration: TLSConfiguration(tlsConfig))
        } catch {
          throw RuntimeError(
            code: .transportError,
            message: "Couldn't create SSL context, check your TLS configuration.",
            cause: error
          )
        }
      }
      #endif

      let serverChannel = try await ServerBootstrap(group: self.eventLoopGroup)
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
            #if canImport(NIOSSL)
            if let nioSSLContext {
              try channel.pipeline.syncOperations.addHandler(
                NIOSSLServerHandler(context: nioSSLContext)
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

      let action = self.listeningAddressState.withLock {
        $0.addressBound(
          serverChannel.channel.localAddress,
          userProvidedAddress: self.address
        )
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

extension NIOCore.SocketAddress {
  fileprivate init(_ socketAddress: GRPCHTTP2Core.SocketAddress) throws {
    if let ipv4 = socketAddress.ipv4 {
      self = try Self(ipv4)
    } else if let ipv6 = socketAddress.ipv6 {
      self = try Self(ipv6)
    } else if let unixDomainSocket = socketAddress.unixDomainSocket {
      self = try Self(unixDomainSocket)
    } else {
      throw RPCError(
        code: .internalError,
        message:
          "Unsupported mapping to NIOCore/SocketAddress for GRPCHTTP2Core/SocketAddress: \(socketAddress)."
      )
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
