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

import DequeModule
import GRPCCore
@_spi(Package) @testable import GRPCHTTP2Core
import NIOCore
import NIOHTTP2
import NIOPosix

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
enum ConnectionTest {
  struct Context {
    var server: Server
    var connection: Connection
  }

  static func run(
    connector: HTTP2Connector,
    server mode: Server.Mode = .regular,
    handlEvents: (
      _ context: Context,
      _ event: Connection.Event
    ) async throws -> Void = { _, _ in },
    validateEvents: (_ context: Context, _ events: [Connection.Event]) throws -> Void
  ) async throws {
    let server = Server(mode: mode)
    let address = try await server.bind()

    try await withThrowingTaskGroup(of: Void.self) { group in
      let connection = Connection(
        address: address,
        http2Connector: connector,
        defaultCompression: .none,
        enabledCompression: .none
      )
      let context = Context(server: server, connection: connection)
      group.addTask { await connection.run() }

      var events: [Connection.Event] = []
      for await event in connection.events {
        events.append(event)
        try await handlEvents(context, event)
      }

      try validateEvents(context, events)
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension ConnectionTest {
  /// A server which only expected to accept a single connection.
  final class Server {
    private let eventLoop: any EventLoop
    private var listener: (any Channel)?
    private let client: EventLoopPromise<Channel>
    private let mode: Mode

    enum Mode {
      case regular
      case closeOnAccept
    }

    init(mode: Mode) {
      self.mode = mode
      self.eventLoop = .singletonMultiThreadedEventLoopGroup.next()
      self.client = self.eventLoop.next().makePromise()
    }

    deinit {
      self.listener?.close(promise: nil)
      self.client.futureResult.whenSuccess { $0.close(mode: .all, promise: nil) }
    }

    var acceptedChannel: Channel {
      get throws {
        try self.client.futureResult.wait()
      }
    }

    func bind() async throws -> GRPCHTTP2Core.SocketAddress {
      precondition(self.listener == nil, "\(#function) must only be called once")

      let hasAcceptedChannel = try await self.eventLoop.submit {
        NIOLoopBoundBox(false, eventLoop: self.eventLoop)
      }.get()

      let bootstrap = ServerBootstrap(group: self.eventLoop).childChannelInitializer { channel in
        precondition(!hasAcceptedChannel.value, "already accepted a channel")
        hasAcceptedChannel.value = true

        switch self.mode {
        case .closeOnAccept:
          return channel.close()

        case .regular:
          return channel.eventLoop.makeCompletedFuture {
            let sync = channel.pipeline.syncOperations
            let h2 = NIOHTTP2Handler(mode: .server)
            let mux = HTTP2StreamMultiplexer(mode: .server, channel: channel) { stream in
              let sync = stream.pipeline.syncOperations
              let handler = GRPCServerStreamHandler(
                scheme: .http,
                acceptedEncodings: .none,
                maximumPayloadSize: .max
              )

              return stream.eventLoop.makeCompletedFuture {
                try sync.addHandler(handler)
                try sync.addHandler(EchoHandler())
              }
            }

            try sync.addHandler(h2)
            try sync.addHandler(mux)
            try sync.addHandlers(SucceedOnSettingsAck(promise: self.client))
          }
        }
      }

      let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
      self.listener = channel
      return .ipv4(host: "127.0.0.1", port: channel.localAddress!.port!)
    }
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension ConnectionTest {
  /// Succeeds a promise when a SETTINGS frame ack has been read.
  private final class SucceedOnSettingsAck: ChannelInboundHandler {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame

    private let promise: EventLoopPromise<Channel>

    init(promise: EventLoopPromise<Channel>) {
      self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let frame = self.unwrapInboundIn(data)
      switch frame.payload {
      case .settings(.ack):
        self.promise.succeed(context.channel)
      default:
        ()
      }

      context.fireChannelRead(data)
    }
  }

  final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = RPCRequestPart
    typealias OutboundOut = RPCResponsePart

    private var received: Deque<RPCRequestPart> = []
    private var receivedEnd = false

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
      if let event = event as? ChannelEvent, event == .inputClosed {
        self.receivedEnd = true
      }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      self.received.append(self.unwrapInboundIn(data))
    }

    func channelReadComplete(context: ChannelHandlerContext) {
      while let part = self.received.popFirst() {
        switch part {
        case .metadata(let metadata):
          var filtered = Metadata()

          // Remove any pseudo-headers.
          for (key, value) in metadata where !key.hasPrefix(":") {
            switch value {
            case .string(let value):
              filtered.addString(value, forKey: key)
            case .binary(let value):
              filtered.addBinary(value, forKey: key)
            }
          }

          context.write(self.wrapOutboundOut(.metadata(filtered)), promise: nil)

        case .message(let message):
          context.write(self.wrapOutboundOut(.message(message)), promise: nil)
        }
      }

      if self.receivedEnd {
        let status = Status(code: .ok, message: "")
        context.write(self.wrapOutboundOut(.status(status, [:])), promise: nil)
      }

      context.flush()
    }
  }
}
