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
import GRPCCore
import GRPCHTTP2Core
import NIOCore
import NIOExtras
import NIOHTTP2
import NIOTransportServices

extension HTTP2ServerTransport {
  /// A NIO Transport Services-backed implementation of a server transport.
  @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
  public struct TransportServices: ServerTransport {
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

    private let listeningAddressState: LockedValueBox<State>

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
          .withLockedValue { try $0.listeningAddressFuture }
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
      config: Config = .defaults,
      eventLoopGroup: NIOTSEventLoopGroup = .singletonNIOTSEventLoopGroup
    ) {
      self.address = address
      self.config = config
      self.eventLoopGroup = eventLoopGroup
      self.serverQuiescingHelper = ServerQuiescingHelper(group: self.eventLoopGroup)

      let eventLoop = eventLoopGroup.any()
      self.listeningAddressState = LockedValueBox(.idle(eventLoop.makePromise()))
    }

    public func listen(
      _ streamHandler: @escaping @Sendable (RPCStream<Inbound, Outbound>) async -> Void
    ) async throws {
      defer {
        switch self.listeningAddressState.withLockedValue({ $0.close() }) {
        case .failPromise(let promise, let error):
          promise.fail(error)
        case .doNothing:
          ()
        }
      }

      let serverChannel = try await NIOTSListenerBootstrap(group: self.eventLoopGroup)
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
              useTLS: false
            )
          }
        }

      let action = self.listeningAddressState.withLockedValue {
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

    public func stopListening() {
      self.serverQuiescingHelper.initiateShutdown(promise: nil)
    }
  }

}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ServerTransport.TransportServices {
  /// Configuration for the ``GRPCHTTP2TransportNIOTransportServices/GRPCHTTP2Core/HTTP2ServerTransport/TransportServices``.
  public struct Config: Sendable {
    /// Compression configuration.
    public var compression: HTTP2ServerTransport.Config.Compression
    /// Connection configuration.
    public var connection: HTTP2ServerTransport.Config.Connection
    /// HTTP2 configuration.
    public var http2: HTTP2ServerTransport.Config.HTTP2
    /// RPC configuration.
    public var rpc: HTTP2ServerTransport.Config.RPC

    /// Construct a new `Config`.
    /// - Parameters:
    ///   - compression: Compression configuration.
    ///   - connection: Connection configuration.
    ///   - http2: HTTP2 configuration.
    ///   - rpc: RPC configuration.
    public init(
      compression: HTTP2ServerTransport.Config.Compression,
      connection: HTTP2ServerTransport.Config.Connection,
      http2: HTTP2ServerTransport.Config.HTTP2,
      rpc: HTTP2ServerTransport.Config.RPC
    ) {
      self.compression = compression
      self.connection = connection
      self.http2 = http2
      self.rpc = rpc
    }

    /// Default values for the different configurations.
    public static var defaults: Self {
      Self(
        compression: .defaults,
        connection: .defaults,
        http2: .defaults,
        rpc: .defaults
      )
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
#endif
