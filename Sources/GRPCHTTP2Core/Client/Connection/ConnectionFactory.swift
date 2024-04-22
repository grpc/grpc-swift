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

import NIOCore
import NIOHTTP2
import NIOPosix

@_spi(Package)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol HTTP2Connector: Sendable {
  func establishConnection(to address: SocketAddress) async throws -> HTTP2Connection
}

@_spi(Package)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct HTTP2Connection {
  /// The underlying TCP connection wrapped up for use with gRPC.
  var channel: NIOAsyncChannel<ClientConnectionEvent, Void>

  /// An HTTP/2 stream multiplexer.
  var multiplexer: NIOHTTP2Handler.AsyncStreamMultiplexer<Void>

  /// Whether the connection is insecure (i.e. plaintext).
  var isPlaintext: Bool

  public init(
    channel: NIOAsyncChannel<ClientConnectionEvent, Void>,
    multiplexer: NIOHTTP2Handler.AsyncStreamMultiplexer<Void>,
    isPlaintext: Bool
  ) {
    self.channel = channel
    self.multiplexer = multiplexer
    self.isPlaintext = isPlaintext
  }
}
