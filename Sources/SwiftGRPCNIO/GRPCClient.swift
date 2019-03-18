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
/// Different service clients implementing `GRPCServiceClient` may share an instance of this class.
open class GRPCClient {
  public static func start(
    host: String,
    port: Int,
    eventLoopGroup: EventLoopGroup,
    sslContext: NIOSSLContext? = nil
  ) throws -> EventLoopFuture<GRPCClient> {
    // We need to capture the multiplexer from the channel initializer to store it after connection.
    let multiplexerPromise: EventLoopPromise<HTTP2StreamMultiplexer> = eventLoopGroup.next().makePromise()

    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      // Enable SO_REUSEADDR.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        let multiplexer = configureSSL(sslContext: sslContext, channel: channel, host: host).flatMap {
          channel.configureHTTP2Pipeline(mode: .client)
        }

        multiplexer.cascade(to: multiplexerPromise)
        return multiplexer.map { _ in }
      }

    return bootstrap.connect(host: host, port: port)
      .and(multiplexerPromise.futureResult)
      .map { channel, multiplexer in GRPCClient(channel: channel, multiplexer: multiplexer, host: host, httpProtocol: sslContext == nil ? .http : .https) }
  }

  /// Configure an SSL handler on the channel, if one is provided.
  ///
  /// - Parameters:
  ///   - sslContext: SSL context to use when creating the handler.
  ///   - channel: The channel on which to add the SSL handler.
  ///   - host: The hostname of the server we're connecting to.
  /// - Returns: A future which will be succeeded when the pipeline has been configured.
  private static func configureSSL(sslContext: NIOSSLContext?, channel: Channel, host: String) -> EventLoopFuture<Void> {
    guard let sslContext = sslContext else {
      return channel.eventLoop.makeSucceededFuture(())
    }

    let handlerAddedPromise: EventLoopPromise<Void> = channel.eventLoop.makePromise()

    do {
      channel.pipeline.addHandler(try NIOSSLClientHandler(context: sslContext, serverHostname: host)).cascade(to: handlerAddedPromise)
    } catch {
      handlerAddedPromise.fail(error)
    }

    return handlerAddedPromise.futureResult
  }

  public let channel: Channel
  public let multiplexer: HTTP2StreamMultiplexer
  public let host: String
  public var defaultCallOptions: CallOptions
  public let httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol

  init(channel: Channel, multiplexer: HTTP2StreamMultiplexer, host: String, httpProtocol: HTTP2ToHTTP1ClientCodec.HTTPProtocol, defaultCallOptions: CallOptions = CallOptions()) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.host = host
    self.defaultCallOptions = defaultCallOptions
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

/// A GRPC client for a given service.
public protocol GRPCServiceClient {
  /// The client providing the underlying HTTP/2 channel for this client.
  var client: GRPCClient { get }

  /// Name of the service this client is for (e.g. "echo.Echo").
  var service: String { get }

  /// The call options to use should the user not provide per-call options.
  var defaultCallOptions: CallOptions { get set }

  /// Return the path for the given method in the format "/Service-Name/Method-Name".
  ///
  /// This may be overriden if consumers require a different path format.
  ///
  /// - Parameter forMethod: name of method to return a path for.
  /// - Returns: path for the given method used in gRPC request headers.
  func path(forMethod method: String) -> String
}

extension GRPCServiceClient {
  public func path(forMethod method: String) -> String {
    return "/\(service)/\(method)"
  }
}
