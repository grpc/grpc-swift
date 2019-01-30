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

public final class GRPCClient {
  public static func start(
    host: String,
    port: Int,
    eventLoopGroup: EventLoopGroup
  ) -> EventLoopFuture<GRPCClient> {
    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      // Enable SO_REUSEADDR.
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        channel.pipeline.add(handler: HTTP2Parser(mode: .client))
    }

    return bootstrap.connect(host: host, port: port).then { (channel: Channel) -> EventLoopFuture<GRPCClient> in
      let multiplexer = HTTP2StreamMultiplexer(inboundStreamStateInitializer: nil)
      return channel.pipeline.add(handler: multiplexer)
        .map { GRPCClient(channel: channel, multiplexer: multiplexer, host: host) }
    }
  }

  public let channel: Channel
  public let multiplexer: HTTP2StreamMultiplexer
  public let host: String

  init(channel: Channel, multiplexer: HTTP2StreamMultiplexer, host: String) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.host = host
  }

  /// Fired when the client shuts down.
  public var onClose: EventLoopFuture<Void> {
    return channel.closeFuture
  }

  public func close() -> EventLoopFuture<Void> {
    return channel.close(mode: .all)
  }
}

public protocol GRPCClientWrapper: CallOptionsProvider {
  var client: GRPCClient { get }

  /// Name of the service this client wrapper is for.
  var service: String { get }

  /// Return the path for the given method in the format "/Service-Name/Method-Name".
  ///
  /// This may be overriden if consumers require a different path format.
  ///
  /// - Parameter forMethod: name of method to return a path for.
  /// - Returns: path for the given method used in gRPC request headers.
  func path(forMethod method: String) -> String
}

extension GRPCClientWrapper {
  public func path(forMethod method: String) -> String {
    return "/\(service)/\(method)"
  }
}

public protocol CallOptionsProvider {
  func defaultCallOptions() -> CallOptions
}

extension CallOptionsProvider {
  public func defaultCallOptions() -> CallOptions {
    return CallOptions()
  }
}
