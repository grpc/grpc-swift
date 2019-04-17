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

/// Underlying channel and HTTP/2 stream multiplexer.
///
/// Different service clients implementing `GRPCClient` may share an instance of this class.
open class GRPCClientConnection {
  /// Starts a connection to the given host and port.
  ///
  /// - Parameters:
  ///   - host: Host to connect to.
  ///   - port: Port on the host to connect to.
  ///   - eventLoopGroup: Event loop group to run the connection on.
  ///   - tlsMode: How TLS should be configured for this connection.
  ///   - hostOverride: Value to use for TLS SNI extension; this must not be an IP address. Ignored
  ///       if `tlsMode` is `.none`.
  /// - Returns: A future which will be fulfilled with a connection to the remote peer.
  public static func start(
    host: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    tls tlsMode: TLSMode = .none,
    hostOverride: String? = nil
  ) throws -> EventLoopFuture<GRPCClientConnection> {
    // We need to capture the multiplexer from the channel initializer to store it after connection.
    let multiplexerPromise: EventLoopPromise<HTTP2StreamMultiplexer> = eventLoopGroup.next().makePromise()

    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      // Enable SO_REUSEADDR.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        let multiplexer = configureTLS(mode: tlsMode, channel: channel, host: hostOverride ?? host).flatMap {
          channel.configureHTTP2Pipeline(mode: .client)
        }

        multiplexer.cascade(to: multiplexerPromise)
        return multiplexer.map { _ in }
      }

    return bootstrap.connect(host: host, port: port)
      .and(multiplexerPromise.futureResult)
      .map { channel, multiplexer in GRPCClientConnection(channel: channel, multiplexer: multiplexer, host: host, httpProtocol: tlsMode.httpProtocol) }
  }

  /// Configure an SSL handler on the channel, if one is required.
  ///
  /// - Parameters:
  ///   - mode: TLS mode to use when creating the new handler.
  ///   - channel: The channel on which to add the SSL handler.
  ///   - host: The hostname of the server we're connecting to.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  private static func configureTLS(mode tls: TLSMode, channel: Channel, host: String) -> EventLoopFuture<Void> {
    let handlerAddedPromise: EventLoopPromise<Void> = channel.eventLoop.makePromise()

    do {
      guard let sslContext = try tls.makeSSLContext() else {
        handlerAddedPromise.succeed(())
        return handlerAddedPromise.futureResult
      }
      channel.pipeline.addHandler(try NIOSSLClientHandler(context: sslContext, serverHostname: host)).cascade(to: handlerAddedPromise)
    } catch {
      handlerAddedPromise.fail(error)
    }

    return handlerAddedPromise.futureResult
  }

  public let channel: Channel
  public let multiplexer: HTTP2StreamMultiplexer
  public let host: String
  public let httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol

  init(channel: Channel, multiplexer: HTTP2StreamMultiplexer, host: String, httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.host = host
    self.httpProtocol = httpProtocol
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
