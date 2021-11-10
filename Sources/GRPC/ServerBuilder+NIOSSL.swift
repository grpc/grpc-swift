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

extension Server {
  /// Returns a `Server` builder configured with TLS.
  @available(
    *, deprecated,
    message: "Use one of 'usingTLSBackedByNIOSSL(on:certificateChain:privateKey:)', 'usingTLSBackedByNetworkFramework(on:with:)' or 'usingTLS(with:on:)'"
  )
  public static func secure(
    group: EventLoopGroup,
    certificateChain: [NIOSSLCertificate],
    privateKey: NIOSSLPrivateKey
  ) -> Builder.Secure {
    return Server.usingTLSBackedByNIOSSL(
      on: group,
      certificateChain: certificateChain,
      privateKey: privateKey
    )
  }

  /// Returns a `Server` builder configured with the 'NIOSSL' TLS backend.
  ///
  /// This builder may use either a `MultiThreadedEventLoopGroup` or a `NIOTSEventLoopGroup` (or an
  /// `EventLoop` from either group).
  public static func usingTLSBackedByNIOSSL(
    on group: EventLoopGroup,
    certificateChain: [NIOSSLCertificate],
    privateKey: NIOSSLPrivateKey
  ) -> Builder.Secure {
    return Builder.Secure(
      group: group,
      tlsConfiguration: .makeServerConfigurationBackedByNIOSSL(
        certificateChain: certificateChain.map { .certificate($0) },
        privateKey: .privateKey(privateKey)
      )
    )
  }
}

extension Server.Builder.Secure {
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

  /// Sets whether certificates should be verified. Defaults to `.none` if not set.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(certificateVerification: CertificateVerification) -> Self {
    self.tls.updateNIOCertificateVerification(to: certificateVerification)
    return self
  }
}

#endif // canImport(NIOSSL)
