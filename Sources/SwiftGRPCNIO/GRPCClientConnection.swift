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

/// Underlying channel and HTTP/2 stream multiplexer.
///
/// Different service clients implementing `GRPCClient` may share an instance of this class.
///
/// The connection is initially setup with a handler to verify that TLS was established
/// successfully (assuming TLS is being used).
///
///                          ▲                       |
///                HTTP2Frame│                       │HTTP2Frame
///                        ┌─┴───────────────────────▼─┐
///                        │   HTTP2StreamMultiplexer  |
///                        └─▲───────────────────────┬─┘
///                HTTP2Frame│                       │HTTP2Frame
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOHTTP2Handler     │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │ GRPCTLSVerificationHandler│
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                        ┌─┴───────────────────────▼─┐
///                        │       NIOSSLHandler       │
///                        └─▲───────────────────────┬─┘
///                ByteBuffer│                       │ByteBuffer
///                          │                       ▼
///
/// The `GRPCTLSVerificationHandler` observes the outcome of the SSL handshake and determines
/// whether a `GRPCClientConnection` should be returned to the user. In either eventuality, the
/// handler removes itself from the pipeline once TLS has been verified. There is also a delegated
/// error handler after the `HTTPStreamMultiplexer` in the main channel which uses the error
/// delegate associated with this connection (see `GRPCDelegatingErrorHandler`).
///
/// See `BaseClientCall` for a description of the remainder of the client pipeline.
open class GRPCClientConnection {
  /// Starts a connection to the given host and port.
  ///
  /// - Parameters:
  ///   - host: Host to connect to.
  ///   - port: Port on the host to connect to.
  ///   - eventLoopGroup: Event loop group to run the connection on.
  ///   - errorDelegate: An error delegate which is called when errors are caught. Provided
  ///       delegates **must not maintain a strong reference to this `GRPCClientConnection`**. Doing
  ///       so will cause a retain cycle. Defaults to a delegate which logs errors in debug builds
  ///       only.
  ///   - tlsMode: How TLS should be configured for this connection.
  ///   - hostOverride: Value to use for TLS SNI extension; this must not be an IP address. Ignored
  ///       if `tlsMode` is `.none`.
  /// - Returns: A future which will be fulfilled with a connection to the remote peer.
  public static func start(
    host: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    errorDelegate: ClientErrorDelegate? = DebugOnlyLoggingClientErrorDelegate.shared,
    tls tlsMode: TLSMode = .none,
    hostOverride: String? = nil
  ) throws -> EventLoopFuture<GRPCClientConnection> {
    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      // Enable SO_REUSEADDR.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        configureTLS(mode: tlsMode, channel: channel, host: hostOverride ?? host, errorDelegate: errorDelegate).flatMap {
          channel.configureHTTP2Pipeline(mode: .client)
        }.flatMap { _ in
          channel.pipeline.addHandler(GRPCDelegatingErrorHandler(delegate: errorDelegate))
        }
      }

    return bootstrap.connect(host: host, port: port).flatMap { channel in
      // Check the handshake succeeded and a valid protocol was negotiated via ALPN.
      let tlsVerified: EventLoopFuture<Void>

      if case .none = tlsMode {
        tlsVerified = channel.eventLoop.makeSucceededFuture(())
      } else {
        // TODO: Use `handler(type:)` introduced in https://github.com/apple/swift-nio/pull/974
        // once it has been released.
        tlsVerified = channel.pipeline.context(handlerType: GRPCTLSVerificationHandler.self).map {
          $0.handler as! GRPCTLSVerificationHandler
        }.flatMap {
          // Use the result of the verification future to determine whether we should return a
          // connection to the caller. Note that even though it contains a `Void` it may also
          // contain an `Error`, which is what we are interested in here.
          $0.verification
        }
      }

      return tlsVerified.flatMap {
        // TODO: Use `handler(type:)` introduced in https://github.com/apple/swift-nio/pull/974
        // once it has been released.
        channel.pipeline.context(handlerType: HTTP2StreamMultiplexer.self)
      }.map {
        $0.handler as! HTTP2StreamMultiplexer
      }.map { multiplexer in
        GRPCClientConnection(channel: channel, multiplexer: multiplexer, host: host, httpProtocol: tlsMode.httpProtocol, errorDelegate: errorDelegate)
      }
    }
  }

  /// Configure an SSL handler on the channel, if one is required.
  ///
  /// - Parameters:
  ///   - mode: TLS mode to use when creating the new handler.
  ///   - channel: The channel on which to add the SSL handler.
  ///   - host: The hostname of the server we're connecting to.
  ///   - errorDelegate: The error delegate to use.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  private static func configureTLS(mode tls: TLSMode, channel: Channel, host: String, errorDelegate: ClientErrorDelegate?) -> EventLoopFuture<Void> {
    let handlerAddedPromise: EventLoopPromise<Void> = channel.eventLoop.makePromise()

    do {
      guard let sslContext = try tls.makeSSLContext() else {
        handlerAddedPromise.succeed(())
        return handlerAddedPromise.futureResult
      }

      let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
      let verificationHandler = GRPCTLSVerificationHandler(errorDelegate: errorDelegate)

      channel.pipeline.addHandlers(sslHandler, verificationHandler).cascade(to: handlerAddedPromise)
    } catch {
      handlerAddedPromise.fail(error)
    }

    return handlerAddedPromise.futureResult
  }

  public let channel: Channel
  public let multiplexer: HTTP2StreamMultiplexer
  public let host: String
  public let httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol
  public let errorDelegate: ClientErrorDelegate?

  init(channel: Channel, multiplexer: HTTP2StreamMultiplexer, host: String, httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol, errorDelegate: ClientErrorDelegate?) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.host = host
    self.httpProtocol = httpProtocol
    self.errorDelegate = errorDelegate
  }

  /// Fired when the client shuts down.
  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}

extension GRPCClientConnection {
  public enum TLSMode {
    case none
    case anonymous
    case custom(NIOSSLContext)

    /// Returns an SSL context for the TLS mode.
    ///
    /// - Returns: An SSL context for the TLS mode, or `nil` if TLS is not being used.
    public func makeSSLContext() throws -> NIOSSLContext? {
      switch self {
      case .none:
        return nil

      case .anonymous:
        return try NIOSSLContext(configuration: .forClient())

      case .custom(let context):
        return context
      }
    }

    /// Rethrns the HTTP protocol for the TLS mode.
    public var httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol {
      switch self {
      case .none:
        return .http

      case .anonymous, .custom:
        return .https
      }
    }
  }
}
