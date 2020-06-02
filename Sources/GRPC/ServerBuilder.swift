/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO
import NIOSSL

extension Server {
  public class Builder {
    private let group: EventLoopGroup
    private var maybeTLS: Server.Configuration.TLS? { return nil }
    private var providers: [CallHandlerProvider] = []
    private var errorDelegate: ServerErrorDelegate?
    private var messageEncoding: ServerMessageEncoding = .disabled
    private var httpTargetWindowSize: Int = 65535

    fileprivate init(group: EventLoopGroup) {
      self.group = group
    }

    public class Secure: Builder {
      private var tls: Server.Configuration.TLS
      override var maybeTLS: Server.Configuration.TLS? {
        return self.tls
      }

      fileprivate init(group: EventLoopGroup, certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey) {
        self.tls = .init(
          certificateChain: certificateChain.map { .certificate($0) },
          privateKey: .privateKey(privateKey)
        )
        super.init(group: group)
      }
    }

    public func bind(host: String, port: Int) -> EventLoopFuture<Server> {
      let configuration = Server.Configuration(
        target: .hostAndPort(host, port),
        eventLoopGroup: self.group,
        serviceProviders: self.providers,
        errorDelegate: self.errorDelegate,
        tls: self.maybeTLS,
        messageEncoding: self.messageEncoding,
        httpTargetWindowSize: self.httpTargetWindowSize
      )
      return Server.start(configuration: configuration)
    }
  }
}

extension Server.Builder {
  /// Sets the server error delegate.
  @discardableResult
  public func withErrorDelegate(_ delegate: ServerErrorDelegate?) -> Self {
    self.errorDelegate = delegate
    return self
  }
}

extension Server.Builder {
  /// Sets the service providers that this server should offer. Note that calling this multiple
  /// times will override any previously set providers.
  public func withServiceProviders(_ providers: [CallHandlerProvider]) -> Self {
    self.providers = providers
    return self
  }
}

extension Server.Builder {
  /// Sets the message compression configuration. Compression is disabled if this is not configured
  /// and any RPCs using compression will not be accepted.
  public func withMessageCompression(_ encoding: ServerMessageEncoding) -> Self {
    self.messageEncoding = encoding
    return self
  }
}

extension Server.Builder.Secure {
  /// Sets the trust roots to use to validate certificates. This only needs to be provided if you
  /// intend to validate certificates. Defaults to the system provided trust store (`.default`) if
  /// not set.
  @discardableResult
  public func withTLS(trustRoots: NIOSSLTrustRoots) -> Self {
    self.tls.trustRoots = trustRoots
    return self
  }

  /// Sets whether certificates should be verified. Defaults to `.fullVerification` if not set.
  @discardableResult
  public func withTLS(certificateVerification: CertificateVerification) -> Self {
    self.tls.certificateVerification = certificateVerification
    return self
  }
}

extension Server.Builder {
  /// Sets the HTTP/2 flow control target window size. Defaults to 65,535 if not explicitly set.
  @discardableResult
  public func withHTTPTargetWindowSize(_ httpTargetWindowSize: Int) -> Self {
    self.httpTargetWindowSize = httpTargetWindowSize
    return self
  }
}

extension Server {
  /// Returns an insecure `Server` builder which is *not configured with TLS*.
  public static func insecure(group: EventLoopGroup) -> Builder {
    return Builder(group: group)
  }

  /// Returns a `Server` builder configured with TLS.
  public static func secure(
    group: EventLoopGroup,
    certificateChain: [NIOSSLCertificate],
    privateKey: NIOSSLPrivateKey
  ) -> Builder.Secure {
    return Builder.Secure(
      group: group,
      certificateChain: certificateChain,
      privateKey: privateKey
    )
  }
}
