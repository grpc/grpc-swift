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
import GRPCHTTP2Core
import NIOCore
import NIOPosix

extension ClientBootstrap {
  @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
  func connect<Result: Sendable>(
    to address: GRPCHTTP2Core.SocketAddress,
    _ configure: @Sendable @escaping (any Channel) -> EventLoopFuture<Result>
  ) async throws -> Result {
    if let ipv4 = address.ipv4 {
      return try await self.connect(to: NIOCore.SocketAddress(ipv4), channelInitializer: configure)
    } else if let ipv6 = address.ipv6 {
      return try await self.connect(to: NIOCore.SocketAddress(ipv6), channelInitializer: configure)
    } else if let uds = address.unixDomainSocket {
      return try await self.connect(to: NIOCore.SocketAddress(uds), channelInitializer: configure)
    } else if let vsock = address.virtualSocket {
      return try await self.connect(to: VsockAddress(vsock), channelInitializer: configure)
    } else {
      throw RuntimeError(
        code: .transportError,
        message: """
          Unhandled socket address '\(address)', this is a gRPC Swift bug. Please file an issue \
          against the project.
          """
      )
    }
  }
}

extension NIOPosix.VsockAddress {
  init(_ address: GRPCHTTP2Core.SocketAddress.VirtualSocket) {
    self.init(
      cid: ContextID(rawValue: address.contextID.rawValue),
      port: Port(rawValue: address.port.rawValue)
    )
  }
}
