/*
 * Copyright 2019, gRPC Authors All rights reserved.
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

extension ClientConnection.Configuration {
  /// TLS configuration for a `ClientConnection`.
  ///
  /// Note that this configuration is a subset of `NIOSSL.TLSConfiguration` where certain options
  /// are removed from the user's control to ensure the configuration complies with the gRPC
  /// specification.
  public struct TLS {
    public private(set) var configuration: TLSConfiguration

    /// Value to use for TLS SNI extension; this must not be an address.
    public var hostnameOverride: String?

    /// The certificates to offer during negotiation. If not present, no certificates will be offered.
    public var certificateChain: [NIOSSLCertificateSource] {
      get {
        return self.configuration.certificateChain
      }
      set {
        self.configuration.certificateChain = newValue
      }
    }

    /// The private key associated with the leaf certificate.
    public var privateKey: NIOSSLPrivateKeySource? {
      get {
        return self.configuration.privateKey
      }
      set {
        self.configuration.privateKey = newValue
      }
    }

    /// The trust roots to use to validate certificates. This only needs to be provided if you
    /// intend to validate certificates.
    public var trustRoots: NIOSSLTrustRoots? {
      get {
        return self.configuration.trustRoots
      }
      set {
        self.configuration.trustRoots = newValue
      }
    }

    /// Whether to verify remote certificates.
    public var certificateVerification: CertificateVerification {
      get {
        return self.configuration.certificateVerification
      }
      set {
        self.configuration.certificateVerification = newValue
      }
    }

    /// A custom verification callback that allows completely overriding the certificate verification logic for this connection.
    public var customVerificationCallback: NIOSSLCustomVerificationCallback?

    /// TLS Configuration with suitable defaults for clients.
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
    public init(
      certificateChain: [NIOSSLCertificateSource] = [],
      privateKey: NIOSSLPrivateKeySource? = nil,
      trustRoots: NIOSSLTrustRoots = .default,
      certificateVerification: CertificateVerification = .fullVerification,
      hostnameOverride: String? = nil,
      customVerificationCallback: NIOSSLCustomVerificationCallback? = nil
    ) {
      self.configuration = .forClient(
        minimumTLSVersion: .tlsv12,
        certificateVerification: certificateVerification,
        trustRoots: trustRoots,
        certificateChain: certificateChain,
        privateKey: privateKey,
        applicationProtocols: GRPCApplicationProtocolIdentifier.client
      )
      self.hostnameOverride = hostnameOverride
      self.customVerificationCallback = customVerificationCallback
    }

    /// Creates a TLS Configuration using the given `NIOSSL.TLSConfiguration`.
    public init(configuration: TLSConfiguration, hostnameOverride: String? = nil) {
      self.configuration = configuration
      self.hostnameOverride = hostnameOverride
    }
  }
}

extension Server.Configuration {
  /// TLS configuration for a `Server`.
  ///
  /// Note that this configuration is a subset of `NIOSSL.TLSConfiguration` where certain options
  /// are removed from the users control to ensure the configuration complies with the gRPC
  /// specification.
  public struct TLS {
    public private(set) var configuration: TLSConfiguration

    /// Whether ALPN is required. Disabling this option may be useful in cases where ALPN is not
    /// supported.
    public var requireALPN: Bool = true

    /// The certificates to offer during negotiation. If not present, no certificates will be
    /// offered.
    public var certificateChain: [NIOSSLCertificateSource] {
      get {
        return self.configuration.certificateChain
      }
      set {
        self.configuration.certificateChain = newValue
      }
    }

    /// The private key associated with the leaf certificate.
    public var privateKey: NIOSSLPrivateKeySource? {
      get {
        return self.configuration.privateKey
      }
      set {
        self.configuration.privateKey = newValue
      }
    }

    /// The trust roots to use to validate certificates. This only needs to be provided if you
    /// intend to validate certificates.
    public var trustRoots: NIOSSLTrustRoots? {
      get {
        return self.configuration.trustRoots
      }
      set {
        self.configuration.trustRoots = newValue
      }
    }

    /// Whether to verify remote certificates.
    public var certificateVerification: CertificateVerification {
      get {
        return self.configuration.certificateVerification
      }
      set {
        self.configuration.certificateVerification = newValue
      }
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
    public init(
      certificateChain: [NIOSSLCertificateSource],
      privateKey: NIOSSLPrivateKeySource,
      trustRoots: NIOSSLTrustRoots = .default,
      certificateVerification: CertificateVerification = .none,
      requireALPN: Bool = true
    ) {
      self.configuration = .forServer(
        certificateChain: certificateChain,
        privateKey: privateKey,
        minimumTLSVersion: .tlsv12,
        certificateVerification: certificateVerification,
        trustRoots: trustRoots,
        applicationProtocols: GRPCApplicationProtocolIdentifier.server
      )
      self.requireALPN = requireALPN
    }

    /// Creates a TLS Configuration using the given `NIOSSL.TLSConfiguration`.
    public init(configuration: TLSConfiguration, requireALPN: Bool = true) {
      self.configuration = configuration
      self.requireALPN = requireALPN
    }
  }
}
