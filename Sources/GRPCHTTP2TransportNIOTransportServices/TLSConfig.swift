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

#if canImport(Network)
public import Network

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension HTTP2ServerTransport.TransportServices.Config {
  /// The security configuration for this connection.
  public struct TransportSecurity: Sendable {
    package enum Wrapped: Sendable {
      case plaintext
      case tls(TLS)
    }

    package let wrapped: Wrapped

    /// This connection is plaintext: no encryption will take place.
    public static let plaintext = Self(wrapped: .plaintext)

    /// This connection will use TLS.
    public static func tls(_ tls: TLS) -> Self {
      Self(wrapped: .tls(tls))
    }
  }

  public struct TLS: Sendable {
    /// A provider for the `SecIdentity` to be used when setting up TLS.
    public var identityProvider: @Sendable () throws -> SecIdentity

    /// Whether ALPN is required.
    ///
    /// If this is set to `true` but the client does not support ALPN, then the connection will be rejected.
    public var requireALPN: Bool

    /// Create a new HTTP2 NIO Transport Services transport TLS config, with some values defaulted:
    /// - `requireALPN` equals `false`
    ///
    /// - Returns: A new HTTP2 NIO Transport Services transport TLS config.
    public static func defaults(
      identityProvider: @Sendable @escaping () throws -> SecIdentity
    ) -> Self {
      Self(
        identityProvider: identityProvider,
        requireALPN: false
      )
    }
  }
}
#endif
