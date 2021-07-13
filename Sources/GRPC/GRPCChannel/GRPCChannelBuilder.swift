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
import Dispatch
import Logging
import NIO
import NIOSSL

#if canImport(Security)
import Security
#endif

extension ClientConnection {
  /// Returns an insecure `ClientConnection` builder which is *not configured with TLS*.
  public static func insecure(group: EventLoopGroup) -> ClientConnection.Builder {
    return Builder(group: group)
  }

  /// Returns a `ClientConnection` builder configured with TLS.
  @available(
    *, deprecated,
    message: "Use one of 'usingPlatformAppropriateTLS(for:)', 'usingTLSBackedByNIOSSL(on:)' or 'usingTLSBackedByNetworkFramework(on:)' or 'usingTLS(on:with:)'"
  )
  public static func secure(group: EventLoopGroup) -> ClientConnection.Builder.Secure {
    return ClientConnection.usingTLSBackedByNIOSSL(on: group)
  }

  /// Returns a `ClientConnection` builder configured with a TLS backend appropriate for the
  /// given `EventLoopGroup`.
  ///
  /// gRPC Swift offers two TLS 'backends'. The 'NIOSSL' backend is available on Darwin and Linux
  /// platforms and delegates to SwiftNIO SSL. On recent Darwin platforms (macOS 10.14+, iOS 12+,
  /// tvOS 12+, and watchOS 5+) the 'Network.framework' backend is available. The two backends have
  /// a number of incompatible configuration options and users are responsible for selecting the
  /// appropriate APIs. The TLS configuration options on the builder document which backends they
  /// support.
  ///
  /// TLS backends must also be used with an appropriate `EventLoopGroup` implementation. The
  /// 'NIOSSL' backend may be used either a `MultiThreadedEventLoopGroup` or a
  /// `NIOTSEventLoopGroup`. The 'Network.framework' backend may only be used with a
  /// `NIOTSEventLoopGroup`.
  ///
  /// This function returns a builder using the `NIOSSL` backend if a `MultiThreadedEventLoopGroup`
  /// is supplied and a 'Network.framework' backend if a `NIOTSEventLoopGroup` is used.
  public static func usingPlatformAppropriateTLS(
    for group: EventLoopGroup
  ) -> ClientConnection.Builder.Secure {
    let networkPreference = NetworkPreference.userDefined(.matchingEventLoopGroup(group))
    return Builder.Secure(
      group: group,
      tlsConfiguration: .makeClientDefault(for: networkPreference)
    )
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

  #if canImport(Network)
  /// Returns a `ClientConnection` builder configured with the Network.framework TLS backend.
  ///
  /// This builder must use a `NIOTSEventLoopGroup` (or an `EventLoop` from a
  /// `NIOTSEventLoopGroup`).
  ///
  /// - Parameter group: The `EventLoopGroup` use for the connection.
  /// - Returns: A builder for a connection using the Network.framework TLS backend.
  @available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
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
  #endif

  /// Returns a `ClientConnection` builder configured with the TLS backend appropriate for the
  /// provided configuration and `EventLoopGroup`.
  ///
  /// - Important: The caller is responsible for ensuring the provided `configuration` may be used
  ///   the the `group`.
  public static func usingTLS(
    with configuration: GRPCTLSConfiguration,
    on group: EventLoopGroup
  ) -> ClientConnection.Builder.Secure {
    return Builder.Secure(group: group, tlsConfiguration: configuration)
  }
}

extension ClientConnection {
  public class Builder {
    private var configuration: ClientConnection.Configuration
    private var maybeTLS: GRPCTLSConfiguration? { return nil }

    private var connectionBackoff = ConnectionBackoff()
    private var connectionBackoffIsEnabled = true

    fileprivate init(group: EventLoopGroup) {
      // This is okay: the configuration is only consumed on a call to `connect` which sets the host
      // and port.
      self.configuration = .default(target: .hostAndPort("", .max), eventLoopGroup: group)
    }

    public func connect(host: String, port: Int) -> ClientConnection {
      // Finish setting up the configuration.
      self.configuration.target = .hostAndPort(host, port)
      self.configuration.connectionBackoff =
        self.connectionBackoffIsEnabled ? self.connectionBackoff : nil
      self.configuration.tlsConfiguration = self.maybeTLS
      return ClientConnection(configuration: self.configuration)
    }
  }
}

extension ClientConnection.Builder {
  public class Secure: ClientConnection.Builder {
    internal var tls: GRPCTLSConfiguration
    override internal var maybeTLS: GRPCTLSConfiguration? {
      return self.tls
    }

    internal init(group: EventLoopGroup, tlsConfiguration: GRPCTLSConfiguration) {
      group.preconditionCompatible(with: tlsConfiguration)
      self.tls = tlsConfiguration
      super.init(group: group)
    }
  }
}

extension ClientConnection.Builder {
  /// Sets the initial connection backoff. That is, the initial time to wait before re-attempting to
  /// establish a connection. Jitter will *not* be applied to the initial backoff. Defaults to
  /// 1 second if not set.
  @discardableResult
  public func withConnectionBackoff(initial amount: TimeAmount) -> Self {
    self.connectionBackoff.initialBackoff = .seconds(from: amount)
    return self
  }

  /// Set the maximum connection backoff. That is, the maximum amount of time to wait before
  /// re-attempting to establish a connection. Note that this time amount represents the maximum
  /// backoff *before* jitter is applied. Defaults to 120 seconds if not set.
  @discardableResult
  public func withConnectionBackoff(maximum amount: TimeAmount) -> Self {
    self.connectionBackoff.maximumBackoff = .seconds(from: amount)
    return self
  }

  /// Backoff is 'jittered' to randomise the amount of time to wait before re-attempting to
  /// establish a connection. The jittered backoff will be no more than `jitter ⨯ unjitteredBackoff`
  /// from `unjitteredBackoff`. Defaults to 0.2 if not set.
  ///
  /// - Precondition: `0 <= jitter <= 1`
  @discardableResult
  public func withConnectionBackoff(jitter: Double) -> Self {
    self.connectionBackoff.jitter = jitter
    return self
  }

  /// The multiplier for scaling the unjittered backoff between attempts to establish a connection.
  /// Defaults to 1.6 if not set.
  @discardableResult
  public func withConnectionBackoff(multiplier: Double) -> Self {
    self.connectionBackoff.multiplier = multiplier
    return self
  }

  /// The minimum timeout to use when attempting to establishing a connection. The connection
  /// timeout for each attempt is the larger of the jittered backoff and the minimum connection
  /// timeout. Defaults to 20 seconds if not set.
  @discardableResult
  public func withConnectionTimeout(minimum amount: TimeAmount) -> Self {
    self.connectionBackoff.minimumConnectionTimeout = .seconds(from: amount)
    return self
  }

  /// Sets the initial and maximum backoff to given amount. Disables jitter and sets the backoff
  /// multiplier to 1.0.
  @discardableResult
  public func withConnectionBackoff(fixed amount: TimeAmount) -> Self {
    let seconds = Double.seconds(from: amount)
    self.connectionBackoff.initialBackoff = seconds
    self.connectionBackoff.maximumBackoff = seconds
    self.connectionBackoff.multiplier = 1.0
    self.connectionBackoff.jitter = 0.0
    return self
  }

  /// Sets the limit on the number of times to attempt to re-establish a connection. Defaults
  /// to `.unlimited` if not set.
  @discardableResult
  public func withConnectionBackoff(retries: ConnectionBackoff.Retries) -> Self {
    self.connectionBackoff.retries = retries
    return self
  }

  /// Sets whether the connection should be re-established automatically if it is dropped. Defaults
  /// to `true` if not set.
  @discardableResult
  public func withConnectionReestablishment(enabled: Bool) -> Self {
    self.connectionBackoffIsEnabled = enabled
    return self
  }

  /// Sets a custom configuration for keepalive
  /// The defaults for client and server are determined by the gRPC keepalive
  /// [documentation] (https://github.com/grpc/grpc/blob/master/doc/keepalive.md).
  @discardableResult
  public func withKeepalive(_ keepalive: ClientConnectionKeepalive) -> Self {
    self.configuration.connectionKeepalive = keepalive
    return self
  }

  /// The amount of time to wait before closing the connection. The idle timeout will start only
  /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start. If a
  /// connection becomes idle, starting a new RPC will automatically create a new connection.
  /// Defaults to 30 minutes if not set.
  @discardableResult
  public func withConnectionIdleTimeout(_ timeout: TimeAmount) -> Self {
    self.configuration.connectionIdleTimeout = timeout
    return self
  }

  /// The behavior used to determine when an RPC should start. That is, whether it should wait for
  /// an active connection or fail quickly if no connection is currently available. Calls will
  /// use `.waitsForConnectivity` by default.
  @discardableResult
  public func withCallStartBehavior(_ behavior: CallStartBehavior) -> Self {
    self.configuration.callStartBehavior = behavior
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets the client error delegate.
  @discardableResult
  public func withErrorDelegate(_ delegate: ClientErrorDelegate?) -> Self {
    self.configuration.errorDelegate = delegate
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets the client connectivity state delegate and the `DispatchQueue` on which the delegate
  /// should be called. If no `queue` is provided then gRPC will create a `DispatchQueue` on which
  /// to run the delegate.
  @discardableResult
  public func withConnectivityStateDelegate(
    _ delegate: ConnectivityStateDelegate?,
    executingOn queue: DispatchQueue? = nil
  ) -> Self {
    self.configuration.connectivityStateDelegate = delegate
    self.configuration.connectivityStateDelegateQueue = queue
    return self
  }
}

// MARK: - Common TLS options

extension ClientConnection.Builder.Secure {
  /// Sets a server hostname override to be used for the TLS Server Name Indication (SNI) extension.
  /// The hostname from `connect(host:port)` is for TLS SNI if this value is not set and hostname
  /// verification is enabled.
  ///
  /// - Note: May be used with the 'NIOSSL' and 'Network.framework' TLS backend.
  /// - Note: `serverHostnameOverride` may not be `nil` when using the 'Network.framework' backend.
  @discardableResult
  public func withTLS(serverHostnameOverride: String?) -> Self {
    self.tls.hostnameOverride = serverHostnameOverride
    return self
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

// MARK: - Network.framework TLS backend options

#if canImport(Network)
extension ClientConnection.Builder.Secure {
  /// Update the local identity.
  ///
  /// - Note: May only be used with the 'Network.framework' TLS backend.
  @discardableResult
  @available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
  public func withTLS(localIdentity: SecIdentity) -> Self {
    self.tls.updateNetworkLocalIdentity(to: localIdentity)
    return self
  }

  /// Update the callback used to verify a trust object during a TLS handshake.
  ///
  /// - Note: May only be used with the 'Network.framework' TLS backend.
  @discardableResult
  @available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
  public func withTLSHandshakeVerificationCallback(
    on queue: DispatchQueue,
    verificationCallback callback: @escaping sec_protocol_verify_t
  ) -> Self {
    self.tls.updateNetworkVerifyCallbackWithQueue(callback: callback, queue: queue)
    return self
  }
}
#endif

extension ClientConnection.Builder {
  /// Sets the HTTP/2 flow control target window size. Defaults to 65,535 if not explicitly set.
  @discardableResult
  public func withHTTPTargetWindowSize(_ httpTargetWindowSize: Int) -> Self {
    self.configuration.httpTargetWindowSize = httpTargetWindowSize
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets the maximum message size the client is permitted to receive in bytes.
  ///
  /// - Precondition: `limit` must not be negative.
  @discardableResult
  public func withMaximumReceiveMessageLength(_ limit: Int) -> Self {
    self.configuration.maximumReceiveMessageLength = limit
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets a logger to be used for background activity such as connection state changes. Defaults
  /// to a no-op logger if not explicitly set.
  ///
  /// Note that individual RPCs will use the logger from `CallOptions`, not the logger specified
  /// here.
  @discardableResult
  public func withBackgroundActivityLogger(_ logger: Logger) -> Self {
    self.configuration.backgroundActivityLogger = logger
    return self
  }
}

extension ClientConnection.Builder {
  /// A channel initializer which will be run after gRPC has initialized each channel. This may be
  /// used to add additional handlers to the pipeline and is intended for debugging.
  ///
  /// - Warning: The initializer closure may be invoked *multiple times*.
  @discardableResult
  public func withDebugChannelInitializer(
    _ debugChannelInitializer: @escaping (Channel) -> EventLoopFuture<Void>
  ) -> Self {
    self.configuration.debugChannelInitializer = debugChannelInitializer
    return self
  }
}

private extension Double {
  static func seconds(from amount: TimeAmount) -> Double {
    return Double(amount.nanoseconds) / 1_000_000_000
  }
}
