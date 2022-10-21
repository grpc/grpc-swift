/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

import NIOCore
#if canImport(NIOSSL)
import NIOSSL
#endif
#if canImport(Network)
import Network
import NIOTransportServices
#endif

// The same as 'TLSVersion' which is defined in NIOSSL which we don't always have.
enum GRPCTLSVersion: Hashable {
  case tlsv1
  case tlsv11
  case tlsv12
  case tlsv13
}

#if canImport(NIOSSL)
extension GRPCTLSVersion {
  init(_ tlsVersion: TLSVersion) {
    switch tlsVersion {
    case .tlsv1:
      self = .tlsv1
    case .tlsv11:
      self = .tlsv11
    case .tlsv12:
      self = .tlsv12
    case .tlsv13:
      self = .tlsv13
    }
  }
}
#endif

#if canImport(Network)
@available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *)
extension GRPCTLSVersion {
  init?(_ metadata: NWProtocolTLS.Metadata) {
    let protocolMetadata = metadata.securityProtocolMetadata

    if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
      let nwTLSVersion = sec_protocol_metadata_get_negotiated_tls_protocol_version(protocolMetadata)
      switch nwTLSVersion {
      case .TLSv10:
        self = .tlsv1
      case .TLSv11:
        self = .tlsv11
      case .TLSv12:
        self = .tlsv12
      case .TLSv13:
        self = .tlsv13
      case .DTLSv10, .DTLSv12:
        return nil
      @unknown default:
        return nil
      }
    } else {
      let sslVersion = sec_protocol_metadata_get_negotiated_protocol_version(protocolMetadata)
      switch sslVersion {
      case .sslProtocolUnknown:
        return nil
      case .tlsProtocol1, .tlsProtocol1Only:
        self = .tlsv1
      case .tlsProtocol11:
        self = .tlsv11
      case .tlsProtocol12:
        self = .tlsv12
      case .tlsProtocol13:
        self = .tlsv13
      case .dtlsProtocol1,
           .dtlsProtocol12,
           .sslProtocol2,
           .sslProtocol3,
           .sslProtocol3Only,
           .sslProtocolAll,
           .tlsProtocolMaxSupported:
        return nil
      @unknown default:
        return nil
      }
    }
  }
}
#endif

extension Channel {
  /// This method tries to get the TLS version from either the Network.framework or NIOSSL
  /// - Precondition: Must be called on the `EventLoop` the `Channel` is running on.
  func getTLSVersionSync(
    file: StaticString = #fileID,
    line: UInt = #line
  ) throws -> GRPCTLSVersion? {
    #if canImport(Network)
    if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
      do {
        // cast can never fail because we explicitly ask for the NWProtocolTLS Metadata.
        // it may still be nil if Network.framework isn't used for TLS in which case we will
        // fall through and try to get the TLS version from NIOSSL
        if let metadata = try self.getMetadataSync(
          definition: NWProtocolTLS.definition,
          file: file,
          line: line
        ) as! NWProtocolTLS.Metadata? {
          return GRPCTLSVersion(metadata)
        }
      } catch is NIOTSChannelIsNotANIOTSConnectionChannel {
        // Not a NIOTS channel, we might be using NIOSSL so try that next.
      }
    }
    #endif
    #if canImport(NIOSSL)
    return try self.pipeline.syncOperations.nioSSL_tlsVersion().map(GRPCTLSVersion.init)
    #else
    return nil
    #endif
  }
}
