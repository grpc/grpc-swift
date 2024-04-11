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
  /// A resolvable target for Virtual Socket addresses.
  ///
  /// ``VirtualSocket`` addresses can be resolved by the ``NameResolvers/VirtualSocket``
  /// resolver which creates a single ``Endpoint`` for target address.
  public struct VirtualSocket: ResolvableTarget {
    public var address: SocketAddress.VirtualSocket

    public init(address: SocketAddress.VirtualSocket) {
      self.address = address
    }
  }
}

extension ResolvableTarget where Self == ResolvableTargets.VirtualSocket {
  /// Creates a new resolvable Virtual Socket target.
  /// - Parameters:
  ///   - contextID: The context ID ('cid') of the service.
  ///   - port: The port to connect to.
  public static func vsock(
    contextID: SocketAddress.VirtualSocket.ContextID,
    port: SocketAddress.VirtualSocket.Port
  ) -> Self {
    let address = SocketAddress.VirtualSocket(contextID: contextID, port: port)
    return ResolvableTargets.VirtualSocket(address: address)
  }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension NameResolvers {
  /// A ``NameResolverFactory`` for ``ResolvableTargets/VirtualSocket`` targets.
  ///
  /// The name resolver for a given target always produces the same values, with a single endpoint.
  /// This resolver doesn't support fetching service configuration.
  public struct VirtualSocket: NameResolverFactory {
    public typealias Target = ResolvableTargets.VirtualSocket

    public init() {}

    public func resolver(for target: Target) -> NameResolver {
      let endpoint = Endpoint(addresses: [.vsock(target.address)])
      let resolutionResult = NameResolutionResult(endpoints: [endpoint], serviceConfig: nil)
      return NameResolver(names: .constant(resolutionResult), updateMode: .pull)
    }
  }
}
