/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

public import GRPCCore
internal import NIOHTTP2

/// A namespace for the HTTP/2 server transport.
public enum HTTP2ServerTransport {}

extension HTTP2ServerTransport {
  /// A namespace for HTTP/2 server transport configuration.
  public enum Config {}
}

extension HTTP2ServerTransport.Config {
  public struct Compression: Sendable {
    /// Compression algorithms enabled for inbound messages.
    ///
    /// - Note: `CompressionAlgorithm.none` is always supported, even if it isn't set here.
    public var enabledAlgorithms: CompressionAlgorithmSet

    /// Creates a new compression configuration.
    ///
    /// - SeeAlso: ``defaults``.
    public init(enabledAlgorithms: CompressionAlgorithmSet) {
      self.enabledAlgorithms = enabledAlgorithms
    }

    /// Default values, compression is disabled.
    public static var defaults: Self {
      Self(enabledAlgorithms: .none)
    }
  }

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public struct Keepalive: Sendable {
    /// The amount of time to wait after reading data before sending a keepalive ping.
    public var time: Duration

    /// The amount of time the server has to respond to a keepalive ping before the connection is closed.
    public var timeout: Duration

    /// Configuration for how the server enforces client keepalive.
    public var clientBehavior: ClientKeepaliveBehavior

    /// Creates a new keepalive configuration.
    public init(
      time: Duration,
      timeout: Duration,
      clientBehavior: ClientKeepaliveBehavior
    ) {
      self.time = time
      self.timeout = timeout
      self.clientBehavior = clientBehavior
    }

    /// Default values. The time after reading data a ping should be sent defaults to 2 hours, the timeout for
    /// keepalive pings defaults to 20 seconds, pings are not permitted when no calls are in progress, and
    /// the minimum allowed interval for clients to send pings defaults to 5 minutes.
    public static var defaults: Self {
      Self(
        time: .seconds(2 * 60 * 60),  // 2 hours
        timeout: .seconds(20),
        clientBehavior: .defaults
      )
    }
  }

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public struct ClientKeepaliveBehavior: Sendable {
    /// The minimum allowed interval the client is allowed to send keep-alive pings.
    /// Pings more frequent than this interval count as 'strikes' and the connection is closed if there are
    /// too many strikes.
    public var minPingIntervalWithoutCalls: Duration

    /// Whether the server allows the client to send keepalive pings when there are no calls in progress.
    public var allowWithoutCalls: Bool

    /// Creates a new configuration for permitted client keepalive behavior.
    public init(
      minPingIntervalWithoutCalls: Duration,
      allowWithoutCalls: Bool
    ) {
      self.minPingIntervalWithoutCalls = minPingIntervalWithoutCalls
      self.allowWithoutCalls = allowWithoutCalls
    }

    /// Default values. The time after reading data a ping should be sent defaults to 2 hours, the timeout for
    /// keepalive pings defaults to 20 seconds, pings are not permitted when no calls are in progress, and
    /// the minimum allowed interval for clients to send pings defaults to 5 minutes.
    public static var defaults: Self {
      Self(minPingIntervalWithoutCalls: .seconds(5 * 60), allowWithoutCalls: false)
    }
  }

  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public struct Connection: Sendable {
    /// The maximum amount of time a connection may exist before being gracefully closed.
    public var maxAge: Duration?

    /// The maximum amount of time that the connection has to close gracefully.
    public var maxGraceTime: Duration?

    /// The maximum amount of time a connection may be idle before it's closed.
    public var maxIdleTime: Duration?

    /// Configuration for keepalive used to detect broken connections.
    ///
    /// - SeeAlso: gRFC A8 for client side keepalive, and gRFC A9 for server connection management.
    public var keepalive: Keepalive

    public init(
      maxAge: Duration?,
      maxGraceTime: Duration?,
      maxIdleTime: Duration?,
      keepalive: Keepalive
    ) {
      self.maxAge = maxAge
      self.maxGraceTime = maxGraceTime
      self.maxIdleTime = maxIdleTime
      self.keepalive = keepalive
    }

    /// Default values. The max connection age, max grace time, and max idle time default to
    /// `nil` (i.e. infinite). See ``HTTP2ServerTransport/Config/Keepalive/defaults`` for keepalive
    /// defaults.
    public static var defaults: Self {
      Self(maxAge: nil, maxGraceTime: nil, maxIdleTime: nil, keepalive: .defaults)
    }
  }

  public struct HTTP2: Sendable {
    /// The maximum frame size to be used in an HTTP/2 connection.
    public var maxFrameSize: Int

    /// The target window size for this connection.
    ///
    /// - Note: This will also be set as the initial window size for the connection.
    public var targetWindowSize: Int

    /// The number of concurrent streams on the HTTP/2 connection.
    public var maxConcurrentStreams: Int?

    public init(
      maxFrameSize: Int,
      targetWindowSize: Int,
      maxConcurrentStreams: Int?
    ) {
      self.maxFrameSize = maxFrameSize
      self.targetWindowSize = targetWindowSize
      self.maxConcurrentStreams = maxConcurrentStreams
    }

    /// Default values. The max frame size defaults to 2^14, the target window size defaults to 2^16-1, and
    /// the max concurrent streams default to infinite.
    public static var defaults: Self {
      Self(
        maxFrameSize: 1 << 14,
        targetWindowSize: (1 << 16) - 1,
        maxConcurrentStreams: nil
      )
    }
  }

  public struct RPC: Sendable {
    /// The maximum request payload size.
    public var maxRequestPayloadSize: Int

    public init(maxRequestPayloadSize: Int) {
      self.maxRequestPayloadSize = maxRequestPayloadSize
    }

    /// Default values. Maximum request payload size defaults to 4MiB.
    public static var defaults: Self {
      Self(maxRequestPayloadSize: 4 * 1024 * 1024)
    }
  }

  public struct TransportSecurity: Sendable {
    private enum Wrapped {
      case plaintext
      case tls(TLS)
    }

    private let wrapped: Wrapped

    /// This connection is plaintext: no encryption will take place.
    public static let plaintext = Self(wrapped: .plaintext)

    /// This connection will use TLS.
    public static func tls(_ tls: TLS) -> Self {
      Self(wrapped: .tls(tls))
    }

    /// Returns the TLS configuration, if the security has been set to ``tls(_:)``.
    public var tlsConfig: TLS? {
      switch wrapped {
      case .plaintext:
        return nil
      case .tls(let config):
        return config
      }
    }
  }

  public struct TLS: Sendable {
    /// The serialization format of the provided certificates and private keys.
    public struct SerializationFormat: Sendable, Equatable {
      private enum Wrapped {
        case pem
        case der
      }

      private let serialization: Wrapped

      public static let pem = Self(serialization: .pem)
      public static let der = Self(serialization: .der)
    }

    public struct CertificateSource: Sendable {
      private enum Wrapped {
        case file(path: String, serializationFormat: SerializationFormat)
        case certificate(bytes: [UInt8], serializationFormat: SerializationFormat)
      }

      private let wrapped: Wrapped

      /// The certificate will be provided via a file.
      public static func file(path: String, serializationFormat: SerializationFormat) -> Self {
        Self(wrapped: .file(path: path, serializationFormat: serializationFormat))
      }

      /// The certificate will be provided as an array of bytes.
      public static func certificate(bytes: [UInt8], serializationFormat: SerializationFormat) -> Self {
        Self(wrapped: .certificate(bytes: bytes, serializationFormat: serializationFormat))
      }

      /// The file path to the location of the certificate, if the source was set to ``file(path:serializationFormat:)``.
      public var filePath: String? {
        switch wrapped {
        case .file(let path, _):
          return path
        case .certificate:
          return nil
        }
      }

      /// The bytes of the certificate, if the source was set to ``certificate(bytes:serializationFormat:)``.
      public var certificateBytes: [UInt8]? {
        switch wrapped {
        case .certificate(let bytes, _):
          return bytes
        case .file:
          return nil
        }
      }

      /// The serialization format of the certificate.
      public var serializationFormat: SerializationFormat {
        switch wrapped {
        case .file(_, let format):
          return format
        case .certificate(_, let format):
          return format
        }
      }
    }

    public struct PrivateKeySource: Sendable {
      private enum Wrapped {
        case file(path: String, serializationFormat: SerializationFormat)
        case privateKey(bytes: [UInt8], serializationFormat: SerializationFormat)
      }

      private let wrapped: Wrapped

      /// The private key will be provided via a file.
      public static func file(path: String, serializationFormat: SerializationFormat) -> Self {
        Self(wrapped: .file(path: path, serializationFormat: serializationFormat))
      }

      /// The private key will be provided as an array of bytes.
      public static func privateKey(bytes: [UInt8], serializationFormat: SerializationFormat) -> Self {
        Self(wrapped: .privateKey(bytes: bytes, serializationFormat: serializationFormat))
      }

      /// The file path to the location of the private key, if the source was set to ``file(path:serializationFormat:)``.
      public var filePath: String? {
        switch wrapped {
        case .file(let path, _):
          return path
        case .privateKey:
          return nil
        }
      }

      /// The bytes of the private key, if the source was set to ``privateKey(bytes:serializationFormat:)``.
      public var privateKeyBytes: [UInt8]? {
        switch wrapped {
        case .privateKey(let bytes, _):
          return bytes
        case .file:
          return nil
        }
      }

      /// The serialization format of the private key.
      public var serializationFormat: SerializationFormat {
        switch wrapped {
        case .file(_, let format):
          return format
        case .privateKey(_, let format):
          return format
        }
      }
    }

    /// The certificate the server will offer during negotiation.
    public var certificateChainSources: [CertificateSource]
    /// The private key associated with the leaf certificate.
    public var privateKeySource: PrivateKeySource
    /// Whether to verify the remote certificate.
    public var verifyClientCertificate: Bool
    /// Whether ALPN is required.
    ///
    /// If this is set to `true` and the protocol negotiation is unsuccessful, then the server bootstrapping
    /// will fail.
    public var requireALPN: Bool
  }
}
