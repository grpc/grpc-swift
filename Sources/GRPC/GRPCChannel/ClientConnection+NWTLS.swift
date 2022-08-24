/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if canImport(Security)
#if canImport(Network)
import NIOCore
import Security

extension ClientConnection {
  /// Returns a ``ClientConnection`` builder configured with the Network.framework TLS backend.
  ///
  /// This builder must use a `NIOTSEventLoopGroup` (or an `EventLoop` from a
  /// `NIOTSEventLoopGroup`).
  ///
  /// - Parameter group: The `EventLoopGroup` use for the connection.
  /// - Returns: A builder for a connection using the Network.framework TLS backend.
  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func usingTLSBackedByNetworkFramework(
    on group: EventLoopGroup
  ) -> ClientConnection.Builder.Secure {
    precondition(
      PlatformSupport.isTransportServicesEventLoopGroup(group),
      "'\(#function)' requires 'group' to be a 'NIOTransportServices.NIOTSEventLoopGroup' or 'NIOTransportServices.QoSEventLoop' (but was '\(type(of: group))'"
    )
    return Builder.Secure(
      group: group,
      tlsConfiguration: .makeClientConfigurationBackedByNetworkFramework()
    )
  }
}

extension ClientConnection.Builder.Secure {
  /// Update the local identity.
  ///
  /// - Note: May only be used with the 'Network.framework' TLS backend.
  @discardableResult
  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public func withTLS(localIdentity: SecIdentity) -> Self {
    self.tls.updateNetworkLocalIdentity(to: localIdentity)
    return self
  }

  /// Update the callback used to verify a trust object during a TLS handshake.
  ///
  /// - Note: May only be used with the 'Network.framework' TLS backend.
  @discardableResult
  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public func withTLSHandshakeVerificationCallback(
    on queue: DispatchQueue,
    verificationCallback callback: @escaping sec_protocol_verify_t
  ) -> Self {
    self.tls.updateNetworkVerifyCallbackWithQueue(callback: callback, queue: queue)
    return self
  }
}

#endif // canImport(Network)
#endif // canImport(Security)
