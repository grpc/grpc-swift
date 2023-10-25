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
import NIOCore
import NIOPosix

#if canImport(Network)
import Security
#endif

extension Server {
  public class Builder {
    private var configuration: Server.Configuration
    private var maybeTLS: GRPCTLSConfiguration? { return nil }

    fileprivate init(group: EventLoopGroup) {
      self.configuration = .default(
        // This is okay: the configuration is only consumed on a call to `bind` which sets the host
        // and port.
        target: .hostAndPort("", .max),
        eventLoopGroup: group,
        serviceProviders: []
      )
    }

    public class Secure: Builder {
      internal var tls: GRPCTLSConfiguration
      override var maybeTLS: GRPCTLSConfiguration? {
        return self.tls
      }

      internal init(group: EventLoopGroup, tlsConfiguration: GRPCTLSConfiguration) {
        group.preconditionCompatible(with: tlsConfiguration)
        self.tls = tlsConfiguration
        super.init(group: group)
      }
    }

    public func bind(host: String, port: Int) -> EventLoopFuture<Server> {
      // Finish setting up the configuration.
      self.configuration.target = .hostAndPort(host, port)
      self.configuration.tlsConfiguration = self.maybeTLS
      return Server.start(configuration: self.configuration)
    }

    public func bind(unixDomainSocketPath path: String) -> EventLoopFuture<Server> {
      self.configuration.target = .unixDomainSocket(path)
      self.configuration.tlsConfiguration = self.maybeTLS
      return Server.start(configuration: self.configuration)
    }

    public func bind(to socketAddress: SocketAddress) -> EventLoopFuture<Server> {
      self.configuration.target = .socketAddress(socketAddress)
      self.configuration.tlsConfiguration = self.maybeTLS
      return Server.start(configuration: self.configuration)
    }

    public func bind(vsockAddress: VsockAddress) -> EventLoopFuture<Server> {
      self.configuration.target = .vsockAddress(vsockAddress)
      self.configuration.tlsConfiguration = self.maybeTLS
      return Server.start(configuration: self.configuration)
    }

    public func bind(to target: BindTarget) -> EventLoopFuture<Server> {
      self.configuration.target = target
      self.configuration.tlsConfiguration = self.maybeTLS
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
  /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start. Unless a
  /// an idle timeout it set connections will not be idled by default.
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

  /// Sets the maximum message size in bytes the server may receive.
  ///
  /// - Precondition: `limit` must not be negative.
  @discardableResult
  public func withMaximumReceiveMessageLength(_ limit: Int) -> Self {
    self.configuration.maximumReceiveMessageLength = limit
    return self
  }
}

extension Server.Builder.Secure {
  /// Sets whether the server's TLS handshake requires a protocol to be negotiated via ALPN. This
  /// defaults to `true` if not otherwise set.
  ///
  /// If this option is set to `false` and no protocol is negotiated via ALPN then the server will
  /// parse the initial bytes on the connection to determine whether HTTP/2 or HTTP/1.1 (gRPC-Web)
  /// is being used and configure the connection appropriately.
  ///
  /// - Note: May only be used with the 'NIOSSL' TLS backend.
  @discardableResult
  public func withTLS(requiringALPN: Bool) -> Self {
    self.tls.requireALPN = requiringALPN
    return self
  }
}

extension Server.Builder {
  /// Sets the HTTP/2 flow control target window size. Defaults to 8MB if not explicitly set.
  /// Values are clamped between 1 and 2^31-1 inclusive.
  @discardableResult
  public func withHTTPTargetWindowSize(_ httpTargetWindowSize: Int) -> Self {
    self.configuration.httpTargetWindowSize = httpTargetWindowSize
    return self
  }

  /// Sets the maximum allowed number of concurrent HTTP/2 streams a client may open for a given
  /// connection. Defaults to 100.
  @discardableResult
  public func withHTTPMaxConcurrentStreams(_ httpMaxConcurrentStreams: Int) -> Self {
    self.configuration.httpMaxConcurrentStreams = httpMaxConcurrentStreams
    return self
  }

  /// Sets the HTTP/2 max frame size. Defaults to 16384. Value are clamped between 2^14 and 2^24-1
  /// octets inclusive (the minimum and maximum permitted values per RFC 7540 § 4.2).
  ///
  /// Raising this value may lower CPU usage for large message at the cost of increasing head of
  /// line blocking for small messages.
  @discardableResult
  public func withHTTPMaxFrameSize(_ httpMaxFrameSize: Int) -> Self {
    self.configuration.httpMaxFrameSize = httpMaxFrameSize
    return self
  }
}

extension Server.Builder {
  /// Set the CORS configuration for gRPC Web.
  @discardableResult
  public func withCORSConfiguration(_ configuration: Server.Configuration.CORS) -> Self {
    self.configuration.webCORS = configuration
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

  #if canImport(Network)
  /// Returns a `Server` builder configured with the 'Network.framework' TLS backend.
  ///
  /// This builder must use a `NIOTSEventLoopGroup`.
  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func usingTLSBackedByNetworkFramework(
    on group: EventLoopGroup,
    with identity: SecIdentity
  ) -> Builder.Secure {
    precondition(
      PlatformSupport.isTransportServicesEventLoopGroup(group),
      "'usingTLSBackedByNetworkFramework(on:with:)' requires 'eventLoopGroup' to be a 'NIOTransportServices.NIOTSEventLoopGroup' or 'NIOTransportServices.QoSEventLoop' (but was '\(type(of: group))'"
    )
    return Builder.Secure(
      group: group,
      tlsConfiguration: .makeServerConfigurationBackedByNetworkFramework(identity: identity)
    )
  }
  #endif

  /// Returns a `Server` builder configured with the TLS backend appropriate for the
  /// provided `configuration` and `EventLoopGroup`.
  ///
  /// - Important: The caller is responsible for ensuring the provided `configuration` may be used
  ///   the the `group`.
  public static func usingTLS(
    with configuration: GRPCTLSConfiguration,
    on group: EventLoopGroup
  ) -> Builder.Secure {
    return Builder.Secure(group: group, tlsConfiguration: configuration)
  }
}
