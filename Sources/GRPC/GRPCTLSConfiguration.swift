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
import NIOSSL

#if canImport(Network)
import Network
import NIOTransportServices
import Security
#endif

/// TLS configuration.
///
/// This structure allow configuring TLS for a wide range of TLS implementations. Some
/// options are removed from the user's control to ensure the configuration complies with
/// the gRPC specification.
public struct GRPCTLSConfiguration {
  fileprivate enum Backend {
    /// Configuration for NIOSSSL.
    case nio(NIOConfiguration)
    #if canImport(Network)
    /// Configuration for Network.framework.
    case network(NetworkConfiguration)
    #endif
  }

  /// The TLS backend.
  private var backend: Backend

  private init(backend: Backend) {
    self.backend = backend
  }

  /// Return the configuration for NIOSSL or `nil` if Network.framework is being used as the
  /// TLS backend.
  internal var nioConfiguration: NIOConfiguration? {
    switch self.backend {
    case let .nio(configuration):
      return configuration
    #if canImport(Network)
    case .network:
      return nil
    #endif
    }
  }

  internal var isNetworkFrameworkTLSBackend: Bool {
    switch self.backend {
    case .nio:
      return false
    #if canImport(Network)
    case .network:
      return true
    #endif
    }
  }

  /// The server hostname override as used by the TLS SNI extension.
  ///
  /// This value is ignored when the configuration is used for a server.
  ///
  /// - Note: when using the Network.framework backend, this value may not be set to `nil`.
  internal var hostnameOverride: String? {
    get {
      switch self.backend {
      case let .nio(config):
        return config.hostnameOverride

      #if canImport(Network)
      case let .network(config):
        return config.hostnameOverride
      #endif
      }
    }

    set {
      switch self.backend {
      case var .nio(config):
        config.hostnameOverride = newValue
        self.backend = .nio(config)

      #if canImport(Network)
      case var .network(config):
        if #available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *) {
          if let hostnameOverride = newValue {
            config.updateHostnameOverride(to: hostnameOverride)
          } else {
            // We can't unset the value so error instead.
            fatalError("Can't unset hostname override when using Network.framework TLS backend.")
            // FIXME: lazily set the value on the backend when applying the options.
          }
        } else {
          // We can only make the `.network` backend if we meet the above availability checks so
          // this should be unreachable.
          preconditionFailure()
        }
        self.backend = .network(config)
      #endif
      }
    }
  }

  /// Whether the configuration requires ALPN to be used.
  ///
  /// The Network.framework backend does not support this option and always requires ALPN.
  internal var requireALPN: Bool {
    get {
      switch self.backend {
      case let .nio(config):
        return config.requireALPN

      #if canImport(Network)
      case .network:
        return true
      #endif
      }
    }
    set {
      switch self.backend {
      case var .nio(config):
        config.requireALPN = newValue
        self.backend = .nio(config)

      #if canImport(Network)
      case .network:
        ()
      #endif
      }
    }
  }

  // Marked to silence the deprecation warning
  @available(*, deprecated)
  internal init(transforming deprecated: ClientConnection.Configuration.TLS) {
    self.backend = .nio(
      .init(
        configuration: deprecated.configuration,
        customVerificationCallback: deprecated.customVerificationCallback,
        hostnameOverride: deprecated.hostnameOverride,
        requireALPN: false // Not currently supported.
      )
    )
  }

  // Marked to silence the deprecation warning
  @available(*, deprecated)
  internal init(transforming deprecated: Server.Configuration.TLS) {
    self.backend = .nio(
      .init(configuration: deprecated.configuration, requireALPN: deprecated.requireALPN)
    )
  }

  @available(*, deprecated)
  internal var asDeprecatedClientConfiguration: ClientConnection.Configuration.TLS? {
    if case let .nio(config) = self.backend {
      var tls = ClientConnection.Configuration.TLS(
        configuration: config.configuration,
        hostnameOverride: config.hostnameOverride
      )
      tls.customVerificationCallback = config.customVerificationCallback
      return tls
    }

    return nil
  }

  @available(*, deprecated)
  internal var asDeprecatedServerConfiguration: Server.Configuration.TLS? {
    if case let .nio(config) = self.backend {
      return Server.Configuration.TLS(configuration: config.configuration)
    }
    return nil
  }
}

// MARK: - NIO Backend

extension GRPCTLSConfiguration {
  internal struct NIOConfiguration {
    var configuration: TLSConfiguration
    var customVerificationCallback: NIOSSLCustomVerificationCallback?
    var hostnameOverride: String?
    // The client doesn't support this yet (https://github.com/grpc/grpc-swift/issues/1042).
    var requireALPN: Bool
  }

  /// TLS Configuration with suitable defaults for clients, using `NIOSSL`.
  ///
  /// This is a wrapper around `NIOSSL.TLSConfiguration` to restrict input to values which comply
  /// with the gRPC protocol.
  ///
  /// - Parameter certificateChain: The certificate to offer during negotiation, defaults to an
  ///     empty array.
  /// - Parameter privateKey: The private key associated with the leaf certificate. This defaults
  ///     to `nil`.
  /// - Parameter trustRoots: The trust roots to validate certificates, this defaults to using a
  ///     root provided by the platform.
  /// - Parameter certificateVerification: Whether to verify the remote certificate. Defaults to
  ///     `.fullVerification`.
  /// - Parameter hostnameOverride: Value to use for TLS SNI extension; this must not be an IP
  ///     address, defaults to `nil`.
  /// - Parameter customVerificationCallback: A callback to provide to override the certificate verification logic,
  ///     defaults to `nil`.
  public static func makeClientConfigurationBackedByNIOSSL(
    certificateChain: [NIOSSLCertificateSource] = [],
    privateKey: NIOSSLPrivateKeySource? = nil,
    trustRoots: NIOSSLTrustRoots = .default,
    certificateVerification: CertificateVerification = .fullVerification,
    hostnameOverride: String? = nil,
    customVerificationCallback: NIOSSLCustomVerificationCallback? = nil
  ) -> GRPCTLSConfiguration {
    var configuration = TLSConfiguration.makeClientConfiguration()
    configuration.minimumTLSVersion = .tlsv12
    configuration.certificateVerification = certificateVerification
    configuration.trustRoots = trustRoots
    configuration.certificateChain = certificateChain
    configuration.privateKey = privateKey
    configuration.applicationProtocols = GRPCApplicationProtocolIdentifier.client

    return GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      configuration: configuration,
      hostnameOverride: hostnameOverride,
      customVerificationCallback: customVerificationCallback
    )
  }

  /// Creates a gRPC TLS Configuration using the given `NIOSSL.TLSConfiguration`.
  ///
  /// - Note: If no ALPN tokens are set in `configuration.applicationProtocols` then "grpc-exp"
  ///   and "h2" will be used.
  /// - Parameters:
  ///   - configuration: The `NIOSSL.TLSConfiguration` to base this configuration on.
  ///   - hostnameOverride: The hostname override to use for the TLS SNI extension.
  public static func makeClientConfigurationBackedByNIOSSL(
    configuration: TLSConfiguration,
    hostnameOverride: String? = nil,
    customVerificationCallback: NIOSSLCustomVerificationCallback? = nil
  ) -> GRPCTLSConfiguration {
    var configuration = configuration

    // Set the ALPN tokens if none were set.
    if configuration.applicationProtocols.isEmpty {
      configuration.applicationProtocols = GRPCApplicationProtocolIdentifier.client
    }

    let nioConfiguration = NIOConfiguration(
      configuration: configuration,
      customVerificationCallback: customVerificationCallback,
      hostnameOverride: hostnameOverride,
      requireALPN: false // We don't currently support this.
    )

    return GRPCTLSConfiguration(backend: .nio(nioConfiguration))
  }

  /// TLS Configuration with suitable defaults for servers.
  ///
  /// This is a wrapper around `NIOSSL.TLSConfiguration` to restrict input to values which comply
  /// with the gRPC protocol.
  ///
  /// - Parameter certificateChain: The certificate to offer during negotiation.
  /// - Parameter privateKey: The private key associated with the leaf certificate.
  /// - Parameter trustRoots: The trust roots to validate certificates, this defaults to using a
  ///     root provided by the platform.
  /// - Parameter certificateVerification: Whether to verify the remote certificate. Defaults to
  ///     `.none`.
  /// - Parameter requireALPN: Whether ALPN is required or not.
  public static func makeServerConfigurationBackedByNIOSSL(
    certificateChain: [NIOSSLCertificateSource],
    privateKey: NIOSSLPrivateKeySource,
    trustRoots: NIOSSLTrustRoots = .default,
    certificateVerification: CertificateVerification = .none,
    requireALPN: Bool = true
  ) -> GRPCTLSConfiguration {
    var configuration = TLSConfiguration.makeServerConfiguration(
      certificateChain: certificateChain,
      privateKey: privateKey
    )

    configuration.minimumTLSVersion = .tlsv12
    configuration.certificateVerification = certificateVerification
    configuration.trustRoots = trustRoots
    configuration.applicationProtocols = GRPCApplicationProtocolIdentifier.server

    return GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      configuration: configuration,
      requireALPN: requireALPN
    )
  }

  /// Creates a gRPC TLS Configuration suitable for servers using the given
  /// `NIOSSL.TLSConfiguration`.
  ///
  /// - Note: If no ALPN tokens are set in `configuration.applicationProtocols` then "grpc-exp",
  ///   "h2", and "http/1.1" will be used.
  /// - Parameters:
  ///   - configuration: The `NIOSSL.TLSConfiguration` to base this configuration on.
  ///   - requiresALPN: Whether the server enforces ALPN. Defaults to `true`.
  public static func makeServerConfigurationBackedByNIOSSL(
    configuration: TLSConfiguration,
    requireALPN: Bool = true
  ) -> GRPCTLSConfiguration {
    var configuration = configuration

    // Set the ALPN tokens if none were set.
    if configuration.applicationProtocols.isEmpty {
      configuration.applicationProtocols = GRPCApplicationProtocolIdentifier.server
    }

    let nioConfiguration = NIOConfiguration(
      configuration: configuration,
      customVerificationCallback: nil,
      hostnameOverride: nil,
      requireALPN: requireALPN
    )

    return GRPCTLSConfiguration(backend: .nio(nioConfiguration))
  }

  @usableFromInline
  internal func makeNIOSSLContext() throws -> NIOSSLContext? {
    switch self.backend {
    case let .nio(configuration):
      return try NIOSSLContext(configuration: configuration.configuration)
    #if canImport(Network)
    case .network:
      return nil
    #endif
    }
  }

  internal var nioSSLCustomVerificationCallback: NIOSSLCustomVerificationCallback? {
    switch self.backend {
    case let .nio(configuration):
      return configuration.customVerificationCallback
    #if canImport(Network)
    case .network:
      return nil
    #endif
    }
  }

  internal mutating func updateNIOCertificateChain(to certificateChain: [NIOSSLCertificate]) {
    self.modifyingNIOConfiguration {
      $0.configuration.certificateChain = certificateChain.map { .certificate($0) }
    }
  }

  internal mutating func updateNIOPrivateKey(to privateKey: NIOSSLPrivateKey) {
    self.modifyingNIOConfiguration {
      $0.configuration.privateKey = .privateKey(privateKey)
    }
  }

  internal mutating func updateNIOTrustRoots(to trustRoots: NIOSSLTrustRoots) {
    self.modifyingNIOConfiguration {
      $0.configuration.trustRoots = trustRoots
    }
  }

  internal mutating func updateNIOCertificateVerification(
    to verification: CertificateVerification
  ) {
    self.modifyingNIOConfiguration {
      $0.configuration.certificateVerification = verification
    }
  }

  internal mutating func updateNIOCustomVerificationCallback(
    to callback: @escaping NIOSSLCustomVerificationCallback
  ) {
    self.modifyingNIOConfiguration {
      $0.customVerificationCallback = callback
    }
  }

  private mutating func modifyingNIOConfiguration(_ modify: (inout NIOConfiguration) -> Void) {
    switch self.backend {
    case var .nio(configuration):
      modify(&configuration)
      self.backend = .nio(configuration)
    #if canImport(Network)
    case .network:
      preconditionFailure()
    #endif
    }
  }
}

// MARK: - Network Backend

#if canImport(Network)
extension GRPCTLSConfiguration {
  internal struct NetworkConfiguration {
    @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
    internal var options: NWProtocolTLS.Options {
      get {
        return self._options as! NWProtocolTLS.Options
      }
      set {
        self._options = newValue
      }
    }

    /// Always a NWProtocolTLS.Options.
    ///
    /// This somewhat insane type-erasure is necessary because we need to availability-guard the NWProtocolTLS.Options
    /// (it isn't available in older SDKs), but we cannot have stored properties guarded by availability in this way, only
    /// computed ones. To that end, we have to erase the type and then un-erase it. This is fairly silly.
    private var _options: Any

    // This is set privately via `updateHostnameOverride(to:)` because we require availability
    // guards to update the value in the underlying `sec_protocol_options`.
    internal private(set) var hostnameOverride: String?

    @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
    init(options: NWProtocolTLS.Options, hostnameOverride: String?) {
      self._options = options
      self.hostnameOverride = hostnameOverride
    }

    @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
    internal mutating func updateHostnameOverride(to hostnameOverride: String) {
      self.hostnameOverride = hostnameOverride
      sec_protocol_options_set_tls_server_name(
        self.options.securityProtocolOptions,
        hostnameOverride
      )
    }
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func makeClientConfigurationBackedByNetworkFramework(
    identity: SecIdentity? = nil,
    hostnameOverride: String? = nil,
    verifyCallbackWithQueue: (sec_protocol_verify_t, DispatchQueue)? = nil
  ) -> GRPCTLSConfiguration {
    let options = NWProtocolTLS.Options()

    if let identity = identity {
      sec_protocol_options_set_local_identity(
        options.securityProtocolOptions,
        sec_identity_create(identity)!
      )
    }

    if let hostnameOverride = hostnameOverride {
      sec_protocol_options_set_tls_server_name(
        options.securityProtocolOptions,
        hostnameOverride
      )
    }

    if let verifyCallbackWithQueue = verifyCallbackWithQueue {
      sec_protocol_options_set_verify_block(
        options.securityProtocolOptions,
        verifyCallbackWithQueue.0,
        verifyCallbackWithQueue.1
      )
    }

    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
    } else {
      sec_protocol_options_set_tls_min_version(options.securityProtocolOptions, .tlsProtocol12)
    }

    for `protocol` in GRPCApplicationProtocolIdentifier.client {
      sec_protocol_options_add_tls_application_protocol(
        options.securityProtocolOptions,
        `protocol`
      )
    }

    return .makeClientConfigurationBackedByNetworkFramework(
      options: options,
      hostnameOverride: hostnameOverride
    )
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func makeClientConfigurationBackedByNetworkFramework(
    options: NWProtocolTLS.Options,
    hostnameOverride: String? = nil
  ) -> GRPCTLSConfiguration {
    let network = NetworkConfiguration(options: options, hostnameOverride: hostnameOverride)
    return GRPCTLSConfiguration(backend: .network(network))
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func makeServerConfigurationBackedByNetworkFramework(
    identity: SecIdentity
  ) -> GRPCTLSConfiguration {
    let options = NWProtocolTLS.Options()

    sec_protocol_options_set_local_identity(
      options.securityProtocolOptions,
      sec_identity_create(identity)!
    )

    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
    } else {
      sec_protocol_options_set_tls_min_version(options.securityProtocolOptions, .tlsProtocol12)
    }

    for `protocol` in GRPCApplicationProtocolIdentifier.server {
      sec_protocol_options_add_tls_application_protocol(
        options.securityProtocolOptions,
        `protocol`
      )
    }

    return GRPCTLSConfiguration.makeServerConfigurationBackedByNetworkFramework(options: options)
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  public static func makeServerConfigurationBackedByNetworkFramework(
    options: NWProtocolTLS.Options
  ) -> GRPCTLSConfiguration {
    let network = NetworkConfiguration(options: options, hostnameOverride: nil)
    return GRPCTLSConfiguration(backend: .network(network))
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  internal mutating func updateNetworkLocalIdentity(to identity: SecIdentity) {
    self.modifyingNetworkConfiguration {
      sec_protocol_options_set_local_identity(
        $0.options.securityProtocolOptions,
        sec_identity_create(identity)!
      )
    }
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  internal mutating func updateNetworkVerifyCallbackWithQueue(
    callback: @escaping sec_protocol_verify_t,
    queue: DispatchQueue
  ) {
    self.modifyingNetworkConfiguration {
      sec_protocol_options_set_verify_block(
        $0.options.securityProtocolOptions,
        callback,
        queue
      )
    }
  }

  private mutating func modifyingNetworkConfiguration(
    _ modify: (inout NetworkConfiguration) -> Void
  ) {
    switch self.backend {
    case var .network(_configuration):
      modify(&_configuration)
      self.backend = .network(_configuration)
    case .nio:
      preconditionFailure()
    }
  }
}
#endif

#if canImport(Network)
extension GRPCTLSConfiguration {
  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  internal func applyNetworkTLSOptions(
    to bootstrap: NIOTSConnectionBootstrap
  ) -> NIOTSConnectionBootstrap {
    switch self.backend {
    case let .network(_configuration):
      return bootstrap.tlsOptions(_configuration.options)

    case .nio:
      // We're using NIOSSL with Network.framework; that's okay and permitted for backwards
      // compatibility.
      return bootstrap
    }
  }

  @available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
  internal func applyNetworkTLSOptions(
    to bootstrap: NIOTSListenerBootstrap
  ) -> NIOTSListenerBootstrap {
    switch self.backend {
    case let .network(_configuration):
      return bootstrap.tlsOptions(_configuration.options)

    case .nio:
      // We're using NIOSSL with Network.framework; that's okay and permitted for backwards
      // compatibility.
      return bootstrap
    }
  }
}

@available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
extension NIOTSConnectionBootstrap {
  internal func tlsOptions(
    from _configuration: GRPCTLSConfiguration
  ) -> NIOTSConnectionBootstrap {
    return _configuration.applyNetworkTLSOptions(to: self)
  }
}

@available(macOS 10.14, iOS 12.0, watchOS 6.0, tvOS 12.0, *)
extension NIOTSListenerBootstrap {
  internal func tlsOptions(
    from _configuration: GRPCTLSConfiguration
  ) -> NIOTSListenerBootstrap {
    return _configuration.applyNetworkTLSOptions(to: self)
  }
}
#endif
