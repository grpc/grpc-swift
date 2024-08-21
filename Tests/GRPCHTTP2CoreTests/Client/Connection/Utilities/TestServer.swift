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
import NIOCore
import NIOHTTP2
import NIOPosix
import Synchronization
import XCTest

@testable import GRPCHTTP2Core

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class TestServer: Sendable {
  private let eventLoopGroup: any EventLoopGroup
  private typealias Stream = NIOAsyncChannel<RPCRequestPart, RPCResponsePart>
  private typealias Multiplexer = NIOHTTP2AsyncSequence<Stream>

  private let connected: Mutex<[any Channel]>

  typealias Inbound = NIOAsyncChannelInboundStream<RPCRequestPart>
  typealias Outbound = NIOAsyncChannelOutboundWriter<RPCResponsePart>

  private let server: Mutex<NIOAsyncChannel<Multiplexer, Never>?>

  init(eventLoopGroup: any EventLoopGroup) {
    self.eventLoopGroup = eventLoopGroup
    self.server = Mutex(nil)
    self.connected = Mutex([])
  }

  enum Target {
    case localhost
    case uds(String)
  }

  var clients: [any Channel] {
    return self.connected.withLock { $0 }
  }

  func bind(to target: Target = .localhost) async throws -> GRPCHTTP2Core.SocketAddress {
    precondition(self.server.withLock { $0 } == nil)

    @Sendable
    func configure(_ channel: any Channel) -> EventLoopFuture<Multiplexer> {
      self.connected.withLock {
        $0.append(channel)
      }

      channel.closeFuture.whenSuccess {
        self.connected.withLock { connected in
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
              maximumPayloadSize: .max,
              methodDescriptorPromise: channel.eventLoop.makePromise(of: MethodDescriptor.self)
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

    self.server.withLock { $0 = server }
    return address
  }

  func run(_ handle: @Sendable @escaping (Inbound, Outbound) async throws -> Void) async throws {
    guard let server = self.server.withLock({ $0 }) else {
      fatalError("bind() must be called first")
    }

    do {
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
    } catch is CancellationError {
      ()
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension TestServer {
  enum RunHandler {
    case echo
    case never
  }

  func run(_ handler: RunHandler) async throws {
    switch handler {
    case .echo:
      try await self.run { inbound, outbound in
        for try await part in inbound {
          switch part {
          case .metadata:
            try await outbound.write(.metadata([:]))
          case .message(let bytes):
            try await outbound.write(.message(bytes))
          }
        }
        try await outbound.write(.status(Status(code: .ok, message: ""), [:]))
      }

    case .never:
      try await self.run { inbound, outbound in
        XCTFail("Unexpected stream")
        try await outbound.write(.status(Status(code: .unavailable, message: ""), [:]))
        outbound.finish()
      }
    }
  }
}
