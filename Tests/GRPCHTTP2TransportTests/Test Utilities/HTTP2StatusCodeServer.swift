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

import GRPCHTTP2Core
import NIOCore
import NIOHPACK
import NIOHTTP2
import NIOPosix

/// An HTTP/2 test server which only responds to request headers by sending response headers and
/// then closing. Each stream will be closed with the ":status" set to the value of the
/// "response-status" header field in the request headers.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class HTTP2StatusCodeServer {
  private let address: EventLoopPromise<GRPCHTTP2Core.SocketAddress.IPv4>
  private let eventLoopGroup: MultiThreadedEventLoopGroup

  var listeningAddress: GRPCHTTP2Core.SocketAddress.IPv4 {
    get async throws {
      try await self.address.futureResult.get()
    }
  }

  init() {
    self.eventLoopGroup = .singleton
    self.address = self.eventLoopGroup.next().makePromise()
  }

  func run() async throws {
    do {
      let channel = try await ServerBootstrap(group: .singletonMultiThreadedEventLoopGroup)
        .bind(host: "127.0.0.1", port: 0) { channel in
          channel.eventLoop.makeCompletedFuture {
            let sync = channel.pipeline.syncOperations
            let multiplexer = try sync.configureAsyncHTTP2Pipeline(mode: .server) { stream in
              stream.eventLoop.makeCompletedFuture {
                try NIOAsyncChannel<HTTP2Frame.FramePayload, HTTP2Frame.FramePayload>(
                  wrappingChannelSynchronously: stream
                )
              }
            }

            let wrapped = try NIOAsyncChannel<HTTP2Frame, HTTP2Frame>(
              wrappingChannelSynchronously: channel
            )

            return (wrapped, multiplexer)
          }
        }

      let port = channel.channel.localAddress!.port!
      self.address.succeed(.init(host: "127.0.0.1", port: port))

      try await channel.executeThenClose { inbound in
        try await withThrowingTaskGroup(of: Void.self) { acceptedGroup in
          for try await (accepted, mux) in inbound {
            acceptedGroup.addTask {
              try await withThrowingTaskGroup(of: Void.self) { connectionGroup in
                // Run the connection.
                connectionGroup.addTask {
                  try await accepted.executeThenClose { inbound, outbound in
                    for try await _ in inbound {}
                  }
                }

                // Consume the streams.
                for try await stream in mux.inbound {
                  connectionGroup.addTask {
                    try await stream.executeThenClose { inbound, outbound in
                      do {
                        for try await frame in inbound {
                          switch frame {
                          case .headers(let requestHeaders):
                            if let status = requestHeaders.headers.first(name: "response-status") {
                              let headers: HPACKHeaders = [":status": "\(status)"]
                              try await outbound.write(
                                .headers(.init(headers: headers, endStream: true))
                              )
                            }

                          default:
                            ()  // Ignore the others
                          }
                        }
                      } catch {
                        // Ignore errors
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch {
      self.address.fail(error)
    }
  }
}
