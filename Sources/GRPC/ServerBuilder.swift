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
import Logging
import NIO
import NIOSSL

extension Server {
  public class Builder {
    private var configuration: Server.Configuration
    private var maybeTLS: Server.Configuration.TLS? { return nil }

    fileprivate init(group: EventLoopGroup) {
      self.configuration = Configuration(
        // This is okay: the configuration is only consumed on a call to `bind` which sets the host
        // and port.
        target: .hostAndPort("", .max),
        eventLoopGroup: group,
        serviceProviders: []
      )
    }

    public class Secure: Builder {
      private var tls: Server.Configuration.TLS
      override var maybeTLS: Server.Configuration.TLS? {
        return self.tls
      }

      fileprivate init(
        group: EventLoopGroup,
        certificateChain: [NIOSSLCertificate],
        privateKey: NIOSSLPrivateKey
      ) {
        self.tls = .init(
          certificateChain: certificateChain.map { .certificate($0) },
          privateKey: .privateKey(privateKey)
        )
        super.init(group: group)
      }
    }

    public func bind(host: String, port: Int) -> EventLoopFuture<Server> {
      // Finish setting up the configuration.
      self.configuration.target = .hostAndPort(host, port)
      self.configuration.tls = self.maybeTLS
      return Server.start(configuration: self.configuration)
    }
  }
}

extension Server.Builder {
  /// Sets the server error delegate.
  @discardableResult
  public func withErrorDelegate(_ delegate: ServerErrorDelegate?) -> Self {
    self.configuration.errorDelegate = delegate
    return self
  }
}

extension Server.Builder {
  /// Sets the service providers that this server should offer. Note that calling this multiple
  /// times will override any previously set providers.
  @discardableResult
  public func withServiceProviders(_ providers: [CallHandlerProvider]) -> Self {
    self.configuration.serviceProviders = providers
    return self
  }
}

extension Server.Builder {
  @discardableResult
  public func withKeepalive(_ keepalive: ServerConnectionKeepalive) -> Self {
    self.configuration.connectionKeepalive = keepalive
    return self
  }
}

extension Server.Builder {
  /// The amount of time to wait before closing connections. The idle timeout will start only
  /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start. Defaults to
  /// 5 minutes if not set.
  @discardableResult
  public func withConnectionIdleTimeout(_ timeout: TimeAmount) -> Self {
    self.configuration.connectionIdleTimeout = timeout
    return self
  }
}

extension Server.Builder {
  /// Sets the message compression configuration. Compression is disabled if this is not configured
  /// and any RPCs using compression will not be accepted.
  @discardableResult
  public func withMessageCompression(_ encoding: ServerMessageEncoding) -> Self {
    self.configuration.messageEncoding = encoding
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

  /// Sets whether certificates should be verified. Defaults to `.none` if not set.
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
    self.configuration.httpTargetWindowSize = httpTargetWindowSize
    return self
  }
}

extension Server.Builder {
  /// Sets the root server logger. Accepted connections will branch from this logger and RPCs on
  /// each connection will use a logger branched from the connections logger. This logger is made
  /// available to service providers via `context`. Defaults to a no-op logger.
  @discardableResult
  public func withLogger(_ logger: Logger) -> Self {
    self.configuration.logger = logger
    return self
  }
}

extension Server.Builder {
  /// A channel initializer which will be run after gRPC has initialized each accepted channel.
  /// This may be used to add additional handlers to the pipeline and is intended for debugging.
  /// This is analogous to `NIO.ServerBootstrap.childChannelInitializer`.
  ///
  /// - Warning: The initializer closure may be invoked *multiple times*. More precisely: it will
  ///   be invoked at most once per accepted connection.
  @discardableResult
  public func withDebugChannelInitializer(
    _ debugChannelInitializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) -> Self {
    self.configuration.debugChannelInitializer = debugChannelInitializer
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
