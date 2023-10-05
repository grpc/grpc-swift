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
#if canImport(NIOSSL)
import NIOCore
import NIOSSL

extension ClientConnection {
  /// Returns a `ClientConnection` builder configured with TLS.
  @available(
    *,
    deprecated,
    message:
      "Use one of 'usingPlatformAppropriateTLS(for:)', 'usingTLSBackedByNIOSSL(on:)' or 'usingTLSBackedByNetworkFramework(on:)' or 'usingTLS(on:with:)'"
  )
  public static func secure(group: EventLoopGroup) -> ClientConnection.Builder.Secure {
    return ClientConnection.usingTLSBackedByNIOSSL(on: group)
  }

  /// Returns a `ClientConnection` builder configured with the 'NIOSSL' TLS backend.
  ///
  /// This builder may use either a `MultiThreadedEventLoopGroup` or a `NIOTSEventLoopGroup` (or an
  /// `EventLoop` from either group).
  ///
  /// - Parameter group: The `EventLoopGroup` use for the connection.
  /// - Returns: A builder for a connection using the NIOSSL TLS backend.
  public static func usingTLSBackedByNIOSSL(
    on group: EventLoopGroup
  ) -> ClientConnection.Builder.Secure {
    return Builder.Secure(group: group, tlsConfiguration: .makeClientConfigurationBackedByNIOSSL())
  }
}

// MARK: - NIOSSL TLS backend options

extension ClientConnection.Builder.Secure {
  /// Sets the sources of certificates to offer during negotiation. No certificates are offered
  /// during negotiation by default.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(certificateChain: [NIOSSLCertificate]) -> Self {
    self.tls.updateNIOCertificateChain(to: certificateChain)
    return self
  }

  /// Sets the private key associated with the leaf certificate.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(privateKey: NIOSSLPrivateKey) -> Self {
    self.tls.updateNIOPrivateKey(to: privateKey)
    return self
  }

  /// Sets the trust roots to use to validate certificates. This only needs to be provided if you
  /// intend to validate certificates. Defaults to the system provided trust store (`.default`) if
  /// not set.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(trustRoots: NIOSSLTrustRoots) -> Self {
    self.tls.updateNIOTrustRoots(to: trustRoots)
    return self
  }

  /// Whether to verify remote certificates. Defaults to `.fullVerification` if not otherwise
  /// configured.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(certificateVerification: CertificateVerification) -> Self {
    self.tls.updateNIOCertificateVerification(to: certificateVerification)
    return self
  }

  /// A custom verification callback that allows completely overriding the certificate verification logic.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLSCustomVerificationCallback(
    _ callback: @escaping NIOSSLCustomVerificationCallback
  ) -> Self {
    self.tls.updateNIOCustomVerificationCallback(to: callback)
    return self
  }
}

#endif  // canImport(NIOSSL)
