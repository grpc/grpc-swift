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
import GRPCCore
import GRPCHTTP2Core
import GRPCHTTP2TransportNIOTransportServices
import XCTest

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class HTTP2TransportNIOTransportServicesTests: XCTestCase {
  private static let p12bundleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // (this file)
    .deletingLastPathComponent()  // GRPCHTTP2TransportTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("Sources")
    .appendingPathComponent("GRPCSampleData")
    .appendingPathComponent("bundle")
    .appendingPathExtension("p12")

  @Sendable private static func loadIdentity() throws -> SecIdentity {
    let data = try Data(contentsOf: Self.p12bundleURL)

    var externalFormat = SecExternalFormat.formatUnknown
    var externalItemType = SecExternalItemType.itemTypeUnknown
    let passphrase = "password" as CFTypeRef
    var exportKeyParams = SecItemImportExportKeyParameters()
    exportKeyParams.passphrase = Unmanaged.passUnretained(passphrase)
    var items: CFArray?

    let status = SecItemImport(
      data as CFData,
      "bundle.p12" as CFString,
      &externalFormat,
      &externalItemType,
      SecItemImportExportFlags(rawValue: 0),
      &exportKeyParams,
      nil,
      &items
    )

    if status != errSecSuccess {
      XCTFail(
        """
        Unable to load identity from '\(Self.p12bundleURL)'. \
        SecItemImport failed with status \(status)
        """
      )
    } else if items == nil {
      XCTFail(
        """
        Unable to load identity from '\(Self.p12bundleURL)'. \
        SecItemImport failed.
        """
      )
    }

    return ((items! as NSArray)[0] as! SecIdentity)
  }

  func testGetListeningAddress_IPv4() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.TransportServices(
      address: .ipv4(host: "0.0.0.0", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _, _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        let ipv4Address = try XCTUnwrap(address.ipv4)
        XCTAssertNotEqual(ipv4Address.port, 0)
        transport.beginGracefulShutdown()
      }
    }
  }

  func testGetListeningAddress_IPv6() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.TransportServices(
      address: .ipv6(host: "::1", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _, _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        let ipv6Address = try XCTUnwrap(address.ipv6)
        XCTAssertNotEqual(ipv6Address.port, 0)
        transport.beginGracefulShutdown()
      }
    }
  }

  func testGetListeningAddress_UnixDomainSocket() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.TransportServices(
      address: .unixDomainSocket(path: "/tmp/niots-uds-test"),
      config: .defaults(transportSecurity: .plaintext)
    )
    defer {
      // NIOTS does not unlink the UDS on close.
      try? FileManager.default.removeItem(atPath: "/tmp/niots-uds-test")
    }

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _, _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertEqual(
          address.unixDomainSocket,
          GRPCHTTP2Core.SocketAddress.UnixDomainSocket(path: "/tmp/niots-uds-test")
        )
        transport.beginGracefulShutdown()
      }
    }
  }

  func testGetListeningAddress_InvalidAddress() async {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.TransportServices(
      address: .unixDomainSocket(path: "/this/should/be/an/invalid/path"),
      config: .defaults(transportSecurity: .plaintext)
    )

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _, _ in }
      }

      group.addTask {
        do {
          _ = try await transport.listeningAddress
          XCTFail("Should have thrown a RuntimeError")
        } catch let error as RuntimeError {
          XCTAssertEqual(error.code, .serverIsStopped)
          XCTAssertEqual(
            error.message,
            """
            There is no listening address bound for this server: there may have \
            been an error which caused the transport to close, or it may have shut down.
            """
          )
        }
      }
    }
  }

  func testGetListeningAddress_StoppedListening() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.TransportServices(
      address: .ipv4(host: "0.0.0.0", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _, _ in }

        do {
          _ = try await transport.listeningAddress
          XCTFail("Should have thrown a RuntimeError")
        } catch let error as RuntimeError {
          XCTAssertEqual(error.code, .serverIsStopped)
          XCTAssertEqual(
            error.message,
            """
            There is no listening address bound for this server: there may have \
            been an error which caused the transport to close, or it may have shut down.
            """
          )
        }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertNotNil(address.ipv4)
        transport.beginGracefulShutdown()
      }
    }
  }

  func testServerConfig_Defaults() throws {
    let identityProvider = Self.loadIdentity
    let grpcTLSConfig = HTTP2ServerTransport.TransportServices.Config.TLS.defaults(
      identityProvider: identityProvider
    )
    let grpcConfig = HTTP2ServerTransport.TransportServices.Config.defaults(
      transportSecurity: .tls(grpcTLSConfig)
    )

    XCTAssertEqual(grpcConfig.compression, HTTP2ServerTransport.Config.Compression.defaults)
    XCTAssertEqual(grpcConfig.connection, HTTP2ServerTransport.Config.Connection.defaults)
    XCTAssertEqual(grpcConfig.http2, HTTP2ServerTransport.Config.HTTP2.defaults)
    XCTAssertEqual(grpcConfig.rpc, HTTP2ServerTransport.Config.RPC.defaults)
    XCTAssertEqual(try grpcTLSConfig.identityProvider(), try identityProvider())
    XCTAssertEqual(grpcTLSConfig.requireALPN, false)
  }

  func testClientConfig_Defaults() throws {
    let identityProvider = Self.loadIdentity
    let grpcTLSConfig = HTTP2ClientTransport.TransportServices.Config.TLS(
      identityProvider: identityProvider
    )
    let grpcConfig = HTTP2ClientTransport.TransportServices.Config.defaults(
      transportSecurity: .tls(grpcTLSConfig)
    )

    XCTAssertEqual(grpcConfig.compression, HTTP2ClientTransport.Config.Compression.defaults)
    XCTAssertEqual(grpcConfig.connection, HTTP2ClientTransport.Config.Connection.defaults)
    XCTAssertEqual(grpcConfig.http2, HTTP2ClientTransport.Config.HTTP2.defaults)
    XCTAssertEqual(grpcConfig.backoff, HTTP2ClientTransport.Config.Backoff.defaults)
    XCTAssertEqual(try grpcTLSConfig.identityProvider(), try identityProvider())
  }
}
#endif
