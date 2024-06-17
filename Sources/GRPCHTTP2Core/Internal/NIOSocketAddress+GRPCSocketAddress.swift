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

@_spi(Package)
public extension GRPCHTTP2Core.SocketAddress {
  init?(_ nioSocketAddress: NIOCore.SocketAddress) {
    switch nioSocketAddress {
    case .v4(let iPv4Address):
      guard let port = nioSocketAddress.port else {
        return nil
      }
      self = .ipv4(host: iPv4Address.host, port: port)

    case .v6(let iPv6Address):
      guard let port = nioSocketAddress.port else {
        return nil
      }
      self = .ipv6(host: iPv6Address.host, port: port)

    case .unixDomainSocket:
      guard let path = nioSocketAddress.pathname else {
        return nil
      }
      self = .unixDomainSocket(path: path)
    }
  }
}

@_spi(Package)
public extension NIOCore.SocketAddress {
  init(_ address: GRPCHTTP2Core.SocketAddress.IPv4) throws {
    try self.init(ipAddress: address.host, port: address.port)
  }

  init(_ address: GRPCHTTP2Core.SocketAddress.IPv6) throws {
    try self.init(ipAddress: address.host, port: address.port)
  }

  init(_ address: GRPCHTTP2Core.SocketAddress.UnixDomainSocket) throws {
    try self.init(unixDomainSocketPath: address.path)
  }
}
