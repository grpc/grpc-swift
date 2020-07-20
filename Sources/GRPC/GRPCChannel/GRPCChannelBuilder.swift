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

extension ClientConnection {
  /// Returns an insecure `ClientConnection` builder which is *not configured with TLS*.
  public static func insecure(group: EventLoopGroup) -> ClientConnection.Builder {
    return Builder(group: group)
  }

  /// Returns a `ClientConnection` builder configured with TLS.
  public static func secure(group: EventLoopGroup) -> ClientConnection.Builder.Secure {
    return Builder.Secure(group: group)
  }
}

extension ClientConnection {
  public class Builder {
    private let group: EventLoopGroup
    private var maybeTLS: ClientConnection.Configuration.TLS? { return nil }
    private var connectionBackoff = ConnectionBackoff()
    private var connectionBackoffIsEnabled = true
    private var errorDelegate: ClientErrorDelegate?
    private var connectivityStateDelegate: ConnectivityStateDelegate?
    private var connectivityStateDelegateQueue: DispatchQueue?
    private var connectionKeepalive = ClientConnectionKeepalive()
    private var connectionIdleTimeout: TimeAmount = .minutes(5)
    private var callStartBehavior: CallStartBehavior = .waitsForConnectivity
    private var httpTargetWindowSize: Int = 65535
    private var logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() })

    fileprivate init(group: EventLoopGroup) {
      self.group = group
    }

    public func connect(host: String, port: Int) -> ClientConnection {
      let configuration = ClientConnection.Configuration(
        target: .hostAndPort(host, port),
        eventLoopGroup: self.group,
        errorDelegate: self.errorDelegate,
        connectivityStateDelegate: self.connectivityStateDelegate,
        connectivityStateDelegateQueue: self.connectivityStateDelegateQueue,
        tls: self.maybeTLS,
        connectionBackoff: self.connectionBackoffIsEnabled ? self.connectionBackoff : nil,
        connectionKeepalive: self.connectionKeepalive,
        connectionIdleTimeout: self.connectionIdleTimeout,
        callStartBehavior: self.callStartBehavior,
        httpTargetWindowSize: self.httpTargetWindowSize,
        backgroundActivityLogger: self.logger
      )
      return ClientConnection(configuration: configuration)
    }
  }
}

extension ClientConnection.Builder {
  public class Secure: ClientConnection.Builder {
    internal var tls = ClientConnection.Configuration.TLS()
    override internal var maybeTLS: ClientConnection.Configuration.TLS? {
      return self.tls
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
    self.connectionKeepalive = keepalive
    return self
  }

  /// The amount of time to wait before closing the connection. The idle timeout will start only
  /// if there are no RPCs in progress and will be cancelled as soon as any RPCs start. If a
  /// connection becomes idle, starting a new RPC will automatically create a new connection.
  /// Defaults to 5 minutes if not set.
  @discardableResult
  public func withConnectionIdleTimeout(_ timeout: TimeAmount) -> Self {
    self.connectionIdleTimeout = timeout
    return self
  }

  /// The behavior used to determine when an RPC should start. That is, whether it should wait for
  /// an active connection or fail quickly if no connection is currently available. Calls will
  /// use `.waitsForConnectivity` by default.
  @discardableResult
  public func withCallStartBehavior(_ behavior: CallStartBehavior) -> Self {
    self.callStartBehavior = behavior
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets the client error delegate.
  @discardableResult
  public func withErrorDelegate(_ delegate: ClientErrorDelegate?) -> Self {
    self.errorDelegate = delegate
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
    self.connectivityStateDelegate = delegate
    self.connectivityStateDelegateQueue = queue
    return self
  }
}

extension ClientConnection.Builder.Secure {
  /// Sets a server hostname override to be used for the TLS Server Name Indication (SNI) extension.
  /// The hostname from `connect(host:port)` is for TLS SNI if this value is not set and hostname
  /// verification is enabled.
  @discardableResult
  public func withTLS(serverHostnameOverride: String?) -> Self {
    self.tls.hostnameOverride = serverHostnameOverride
    return self
  }

  /// Sets the sources of certificates to offer during negotiation. No certificates are offered
  /// during negotiation by default.
  @discardableResult
  public func withTLS(certificateChain: [NIOSSLCertificate]) -> Self {
    // `.certificate` is the only non-deprecated case in `NIOSSLCertificateSource`
    self.tls.certificateChain = certificateChain.map { .certificate($0) }
    return self
  }

  /// Sets the private key associated with the leaf certificate.
  @discardableResult
  public func withTLS(privateKey: NIOSSLPrivateKey) -> Self {
    // `.privateKey` is the only non-deprecated case in `NIOSSLPrivateKeySource`
    self.tls.privateKey = .privateKey(privateKey)
    return self
  }

  /// Sets the trust roots to use to validate certificates. This only needs to be provided if you
  /// intend to validate certificates. Defaults to the system provided trust store (`.default`) if
  /// not set.
  @discardableResult
  public func withTLS(trustRoots: NIOSSLTrustRoots) -> Self {
    self.tls.trustRoots = trustRoots
    return self
  }
}

extension ClientConnection.Builder {
  /// Sets the HTTP/2 flow control target window size. Defaults to 65,535 if not explicitly set.
  @discardableResult
  public func withHTTPTargetWindowSize(_ httpTargetWindowSize: Int) -> Self {
    self.httpTargetWindowSize = httpTargetWindowSize
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
    self.logger = logger
    return self
  }
}

fileprivate extension Double {
  static func seconds(from amount: TimeAmount) -> Double {
    return Double(amount.nanoseconds) / 1_000_000_000
  }
}
