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

import GRPCCore
@_spi(Package) @testable import GRPCHTTP2Core
import NIOCore
import NIOHTTP2
import NIOPosix

@_spi(Package)
extension HTTP2Connector where Self == ThrowingConnector {
  /// A connector which throws the given error on a connect attempt.
  static func throwing(_ error: RPCError) -> Self {
    return ThrowingConnector(error: error)
  }
}

@_spi(Package)
extension HTTP2Connector where Self == NeverConnector {
  /// A connector which fatal errors if a connect attempt is made.
  static var never: Self {
    NeverConnector()
  }
}

@_spi(Package)
extension HTTP2Connector where Self == NIOPosixConnector {
  /// A connector which uses NIOPosix to establish a connection.
  static func posix(
    maxIdleTime: TimeAmount? = nil,
    keepaliveTime: TimeAmount? = nil,
    keepaliveTimeout: TimeAmount? = nil,
    keepaliveWithoutCalls: Bool = false,
    dropPingAcks: Bool = false
  ) -> Self {
    return NIOPosixConnector(
      maxIdleTime: maxIdleTime,
      keepaliveTime: keepaliveTime,
      keepaliveTimeout: keepaliveTimeout,
      keepaliveWithoutCalls: keepaliveWithoutCalls,
      dropPingAcks: dropPingAcks
    )
  }
}

struct ThrowingConnector: HTTP2Connector {
  private let error: RPCError

  init(error: RPCError) {
    self.error = error
  }

  func establishConnection(
    to address: GRPCHTTP2Core.SocketAddress
  ) async throws -> HTTP2Connection {
    throw self.error
  }
}

struct NeverConnector: HTTP2Connector {
  func establishConnection(
    to address: GRPCHTTP2Core.SocketAddress
  ) async throws -> HTTP2Connection {
    fatalError("\(#function) called unexpectedly")
  }
}

struct NIOPosixConnector: HTTP2Connector {
  private let eventLoopGroup: any EventLoopGroup
  private let maxIdleTime: TimeAmount?
  private let keepaliveTime: TimeAmount?
  private let keepaliveTimeout: TimeAmount?
  private let keepaliveWithoutCalls: Bool
  private let dropPingAcks: Bool

  init(
    eventLoopGroup: (any EventLoopGroup)? = nil,
    maxIdleTime: TimeAmount? = nil,
    keepaliveTime: TimeAmount? = nil,
    keepaliveTimeout: TimeAmount? = nil,
    keepaliveWithoutCalls: Bool = false,
    dropPingAcks: Bool = false
  ) {
    self.eventLoopGroup = eventLoopGroup ?? .singletonMultiThreadedEventLoopGroup
    self.maxIdleTime = maxIdleTime
    self.keepaliveTime = keepaliveTime
    self.keepaliveTimeout = keepaliveTimeout
    self.keepaliveWithoutCalls = keepaliveWithoutCalls
    self.dropPingAcks = dropPingAcks
  }

  func establishConnection(
    to address: GRPCHTTP2Core.SocketAddress
  ) async throws -> HTTP2Connection {
    return try await ClientBootstrap(group: self.eventLoopGroup).connect(to: address) { channel in
      channel.eventLoop.makeCompletedFuture {
        let sync = channel.pipeline.syncOperations

        let multiplexer = try sync.configureAsyncHTTP2Pipeline(mode: .client) { stream in
          // Server shouldn't be opening streams.
          stream.close()
        }

        if self.dropPingAcks {
          try sync.addHandler(PingAckDropper())
        }

        let connectionHandler = ClientConnectionHandler(
          eventLoop: channel.eventLoop,
          maxIdleTime: self.maxIdleTime,
          keepaliveTime: self.keepaliveTime,
          keepaliveTimeout: self.keepaliveTimeout,
          keepaliveWithoutCalls: self.keepaliveWithoutCalls
        )

        try sync.addHandler(connectionHandler)

        let asyncChannel = try NIOAsyncChannel<ClientConnectionEvent, Void>(
          wrappingChannelSynchronously: channel
        )

        return HTTP2Connection(channel: asyncChannel, multiplexer: multiplexer, isPlaintext: true)
      }
    }
  }

  /// Drops all acks for PING frames. This is useful to help trigger the keepalive timeout.
  final class PingAckDropper: ChannelInboundHandler {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let frame = self.unwrapInboundIn(data)
      switch frame.payload {
      case .ping(_, ack: true):
        ()  // drop-it
      default:
        context.fireChannelRead(data)
      }
    }
  }
}
