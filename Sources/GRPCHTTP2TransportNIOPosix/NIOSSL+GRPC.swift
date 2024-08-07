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
#if canImport(NIOSSL)
import NIOSSL

extension NIOSSLSerializationFormats {
  fileprivate init(_ format: HTTP2ServerTransport.Config.TLS.SerializationFormat) {
    switch format.wrapped {
    case .pem:
      self = .pem
    case .der:
      self = .der
    }
  }
}

extension Sequence<HTTP2ServerTransport.Config.TLS.CertificateSource> {
  func sslCertificateSources() throws -> [NIOSSLCertificateSource] {
    var certificateSources: [NIOSSLCertificateSource] = []
    for source in self {
      switch source.wrapped {
      case .bytes(let bytes, let serializationFormat):
        switch serializationFormat.wrapped {
        case .der:
          certificateSources.append(
            .certificate(try NIOSSLCertificate(bytes: bytes, format: .der))
          )

        case .pem:
          let certificates = try NIOSSLCertificate.fromPEMBytes(bytes).map {
            NIOSSLCertificateSource.certificate($0)
          }
          certificateSources.append(contentsOf: certificates)
        }

      case .file(let path, let serializationFormat):
        switch serializationFormat.wrapped {
        case .der:
          certificateSources.append(
            .certificate(try NIOSSLCertificate(file: path, format: .der))
          )

        case .pem:
          let certificates = try NIOSSLCertificate.fromPEMFile(path).map {
            NIOSSLCertificateSource.certificate($0)
          }
          certificateSources.append(contentsOf: certificates)
        }
      }
    }
    return certificateSources
  }
}

extension NIOSSLPrivateKey {
  fileprivate convenience init(
    privateKeySource source: HTTP2ServerTransport.Config.TLS.PrivateKeySource
  ) throws {
    switch source.wrapped {
    case .file(let path, let serializationFormat):
      try self.init(
        file: path,
        format: NIOSSLSerializationFormats(serializationFormat)
      )
    case .bytes(let bytes, let serializationFormat):
      try self.init(
        bytes: bytes,
        format: NIOSSLSerializationFormats(serializationFormat)
      )
    }
  }
}

extension NIOSSLTrustRoots {
  fileprivate init(_ trustRoots: HTTP2ServerTransport.Config.TLS.TrustRootsSource) throws {
    switch trustRoots.wrapped {
    case .certificates(let certificateSources):
      let certificates = try certificateSources.map { source in
        switch source.wrapped {
        case .bytes(let bytes, let serializationFormat):
          return try NIOSSLCertificate(
            bytes: bytes,
            format: NIOSSLSerializationFormats(serializationFormat)
          )
        case .file(let path, let serializationFormat):
          return try NIOSSLCertificate(
            file: path,
            format: NIOSSLSerializationFormats(serializationFormat)
          )
        }
      }
      self = .certificates(certificates)

    case .systemDefault:
      self = .default
    }
  }
}

extension TLSConfiguration {
  package init(_ tlsConfig: HTTP2ServerTransport.Config.TLS) throws {
    let certificateChain = try tlsConfig.certificateChainSources.sslCertificateSources()
    let privateKey = try NIOSSLPrivateKey(privateKeySource: tlsConfig.privateKeySource)

    var tlsConfiguration = TLSConfiguration.makeServerConfiguration(
      certificateChain: certificateChain,
      privateKey: .privateKey(privateKey)
    )
    tlsConfiguration.minimumTLSVersion = .tlsv12
    tlsConfiguration.certificateVerification =
      tlsConfig.verifyClientCertificate ? .fullVerification : .none
    tlsConfiguration.trustRoots = try NIOSSLTrustRoots(tlsConfig.trustRoots)
    tlsConfiguration.applicationProtocols = ["grpc-exp", "h2"]

    self = tlsConfiguration
  }
}
#endif
