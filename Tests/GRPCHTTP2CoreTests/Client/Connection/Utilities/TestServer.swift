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
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP2
import NIOPosix

@testable import GRPCHTTP2Core

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class TestServer: Sendable {
  private let eventLoopGroup: any EventLoopGroup
  private typealias Stream = NIOAsyncChannel<RPCRequestPart, RPCResponsePart>
  private typealias Multiplexer = NIOHTTP2AsyncSequence<Stream>

  private let connected: NIOLockedValueBox<[Channel]>

  typealias Inbound = NIOAsyncChannelInboundStream<RPCRequestPart>
  typealias Outbound = NIOAsyncChannelOutboundWriter<RPCResponsePart>

  private let server: NIOLockedValueBox<NIOAsyncChannel<Multiplexer, Never>?>

  init(eventLoopGroup: any EventLoopGroup) {
    self.eventLoopGroup = eventLoopGroup
    self.server = NIOLockedValueBox(nil)
    self.connected = NIOLockedValueBox([])
  }

  enum Target {
    case localhost
    case uds(String)
  }

  var clients: [Channel] {
    return self.connected.withLockedValue { $0 }
  }

  func bind(to target: Target = .localhost) async throws -> GRPCHTTP2Core.SocketAddress {
    precondition(self.server.withLockedValue { $0 } == nil)

    @Sendable
    func configure(_ channel: Channel) -> EventLoopFuture<Multiplexer> {
      self.connected.withLockedValue {
        $0.append(channel)
      }

      channel.closeFuture.whenSuccess {
        self.connected.withLockedValue { connected in
          guard let index = connected.firstIndex(where: { $0 === channel }) else { return }
          connected.remove(at: index)
        }
      }

      return channel.eventLoop.makeCompletedFuture {
        let sync = channel.pipeline.syncOperations
        let multiplexer = try sync.configureAsyncHTTP2Pipeline(mode: .server) { stream in
          stream.eventLoop.makeCompletedFuture {
            let handler = GRPCServerStreamHandler(
              scheme: .http,
              acceptedEncodings: .all,
              maximumPayloadSize: .max
            )

            try stream.pipeline.syncOperations.addHandlers(handler)
            return try NIOAsyncChannel(
              wrappingChannelSynchronously: stream,
              configuration: .init(
                inboundType: RPCRequestPart.self,
                outboundType: RPCResponsePart.self
              )
            )
          }
        }

        return multiplexer.inbound
      }
    }

    let bootstrap = ServerBootstrap(group: self.eventLoopGroup)
    let server: NIOAsyncChannel<Multiplexer, Never>
    let address: GRPCHTTP2Core.SocketAddress

    switch target {
    case .localhost:
      server = try await bootstrap.bind(host: "127.0.0.1", port: 0) { channel in
        configure(channel)
      }
      address = .ipv4(host: "127.0.0.1", port: server.channel.localAddress!.port!)

    case .uds(let path):
      server = try await bootstrap.bind(unixDomainSocketPath: path, cleanupExistingSocketFile: true)
      { channel in
        configure(channel)
      }
      address = .unixDomainSocket(path: server.channel.localAddress!.pathname!)
    }

    self.server.withLockedValue { $0 = server }
    return address
  }

  func run(_ handle: @Sendable @escaping (Inbound, Outbound) async throws -> Void) async throws {
    guard let server = self.server.withLockedValue({ $0 }) else {
      fatalError("bind() must be called first")
    }

    try await server.executeThenClose { inbound, _ in
      try await withThrowingTaskGroup(of: Void.self) { multiplexerGroup in
        for try await multiplexer in inbound {
          multiplexerGroup.addTask {
            try await withThrowingTaskGroup(of: Void.self) { streamGroup in
              for try await stream in multiplexer {
                streamGroup.addTask {
                  try await stream.executeThenClose { inbound, outbound in
                    try await handle(inbound, outbound)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
