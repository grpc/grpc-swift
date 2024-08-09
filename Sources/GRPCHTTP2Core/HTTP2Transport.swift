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

/// A namespace for the HTTP/2 transport.
public enum HTTP2Transport {}

extension HTTP2Transport {
  /// A namespace for HTTP/2 transport configuration shared between client and server.
  public enum Config {}
}

extension HTTP2Transport.Config {
  public enum TLS {
    /// The serialization format of the provided certificates and private keys.
    public struct SerializationFormat: Sendable, Equatable {
      package enum Wrapped {
        case pem
        case der
      }

      package let wrapped: Wrapped

      public static let pem = Self(wrapped: .pem)
      public static let der = Self(wrapped: .der)
    }

    /// A description of where a certificate is coming from: either a byte array or a file.
    /// The serialization format is specified by ``HTTP2Transport/Config/TLS/SerializationFormat``.
    public struct CertificateSource: Sendable {
      package enum Wrapped {
        case file(path: String, format: SerializationFormat)
        case bytes(bytes: [UInt8], format: SerializationFormat)
      }

      package let wrapped: Wrapped

      /// The certificate will be provided via a file.
      public static func file(path: String, format: SerializationFormat) -> Self {
        Self(wrapped: .file(path: path, format: format))
      }

      /// The certificate will be provided as an array of bytes.
      public static func bytes(_ bytes: [UInt8], format: SerializationFormat) -> Self {
        Self(wrapped: .bytes(bytes: bytes, format: format))
      }
    }

    /// A description of where a certificate is coming from: either a byte array or a file.
    /// The serialization format is specified by ``HTTP2Transport/Config/TLS/SerializationFormat``.
    public struct PrivateKeySource: Sendable {
      package enum Wrapped {
        case file(path: String, format: SerializationFormat)
        case bytes(bytes: [UInt8], format: SerializationFormat)
      }

      package let wrapped: Wrapped

      /// The private key will be provided via a file.
      public static func file(path: String, format: SerializationFormat) -> Self {
        Self(wrapped: .file(path: path, format: format))
      }

      /// The private key will be provided as an array of bytes.
      public static func bytes(
        _ bytes: [UInt8],
        format: SerializationFormat
      ) -> Self {
        Self(wrapped: .bytes(bytes: bytes, format: format))
      }
    }
  }
}

extension HTTP2Transport {
  public struct Error: Sendable, Swift.Error {
    public var message: String
    public var cause: any Swift.Error

    public init(message: String, cause: any Swift.Error) {
      self.message = message
      self.cause = cause
    }
  }
}
