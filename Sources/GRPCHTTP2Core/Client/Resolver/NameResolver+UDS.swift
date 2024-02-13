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

extension ResolvableTargets {
  /// A resolvable target for Unix Domain Socket address.
  ///
  /// ``UnixDomainSocket`` addresses can be resolved by the ``NameResolvers/UnixDomainSocket``
  /// resolver which creates a single ``Endpoint`` for target address.
  public struct UnixDomainSocket: ResolvableTarget {
    /// The Unix Domain Socket address.
    public var address: SocketAddress.UnixDomainSocket

    /// Create a new Unix Domain Socket address.
    public init(address: SocketAddress.UnixDomainSocket) {
      self.address = address
    }
  }
}

extension ResolvableTarget where Self == ResolvableTargets.UnixDomainSocket {
  /// Creates a new resolvable Unix Domain Socket target.
  /// - Parameter path: The path of the socket.
  public static func unixDomainSocket(path: String) -> Self {
    return Self(address: SocketAddress.UnixDomainSocket(path: path))
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension NameResolvers {
  /// A ``NameResolverFactory`` for ``ResolvableTargets/UnixDomainSocket`` targets.
  ///
  /// The name resolver for a given target always produces the same values, with a single endpoint.
  /// This resolver doesn't support fetching service configuration.
  public struct UnixDomainSocket: NameResolverFactory {
    public typealias Target = ResolvableTargets.UnixDomainSocket

    public init() {}

    public func resolver(for target: Target) -> NameResolver {
      let endpoint = Endpoint(addresses: [.unixDomainSocket(target.address)])
      let resolutionResult = NameResolutionResult(endpoints: [endpoint], serviceConfiguration: nil)
      return NameResolver(names: .constant(resolutionResult), updateMode: .pull)
    }
  }
}
