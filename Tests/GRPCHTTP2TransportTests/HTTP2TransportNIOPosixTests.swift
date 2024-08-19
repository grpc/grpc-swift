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

private import GRPCCore
private import GRPCHTTP2Core
private import GRPCHTTP2TransportNIOPosix
internal import XCTest

#if canImport(NIOSSL)
private import NIOSSL
#endif

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class HTTP2TransportNIOPosixTests: XCTestCase {
  func testGetListeningAddress_IPv4() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .ipv4(host: "0.0.0.0", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        let ipv4Address = try XCTUnwrap(address.ipv4)
        XCTAssertNotEqual(ipv4Address.port, 0)
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_IPv6() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .ipv6(host: "::1", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        let ipv6Address = try XCTUnwrap(address.ipv6)
        XCTAssertNotEqual(ipv6Address.port, 0)
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_UnixDomainSocket() async throws {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .unixDomainSocket(path: "/tmp/posix-uds-test"),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertEqual(
          address.unixDomainSocket,
          GRPCHTTP2Core.SocketAddress.UnixDomainSocket(path: "/tmp/posix-uds-test")
        )
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_Vsock() async throws {
    try XCTSkipUnless(self.vsockAvailable(), "Vsock unavailable")

    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .vsock(contextID: .any, port: .any),
      config: .defaults(transportSecurity: .plaintext)
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
      }

      group.addTask {
        let address = try await transport.listeningAddress
        XCTAssertNotNil(address.virtualSocket)
        transport.stopListening()
      }
    }
  }

  func testGetListeningAddress_InvalidAddress() async {
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .unixDomainSocket(path: "/this/should/be/an/invalid/path"),
      config: .defaults(transportSecurity: .plaintext)
    )

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }
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
    let transport = GRPCHTTP2Core.HTTP2ServerTransport.Posix(
      address: .ipv4(host: "0.0.0.0", port: 0),
      config: .defaults(transportSecurity: .plaintext)
    )

    try? await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await transport.listen { _ in }

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
        transport.stopListening()
      }
    }
  }

  #if canImport(NIOSSL)
  static let samplePemCert = """
    -----BEGIN CERTIFICATE-----
    MIIGGzCCBAOgAwIBAgIJAJ/X0Fo0ynmEMA0GCSqGSIb3DQEBCwUAMIGjMQswCQYD
    VQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2FuIEZyYW5z
    b2t5bzEuMCwGA1UECgwlU2FuIEZyYW5zb2t5byBJbnN0aXR1dGUgb2YgVGVjaG5v
    bG9neTEVMBMGA1UECwwMUm9ib3RpY3MgTGFiMSAwHgYDVQQDDBdyb2JvdHMuc2Fu
    ZnJhbnNva3lvLmVkdTAeFw0xNzEwMTYyMTAxMDJaFw00NzEwMDkyMTAxMDJaMIGj
    MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNU2Fu
    IEZyYW5zb2t5bzEuMCwGA1UECgwlU2FuIEZyYW5zb2t5byBJbnN0aXR1dGUgb2Yg
    VGVjaG5vbG9neTEVMBMGA1UECwwMUm9ib3RpY3MgTGFiMSAwHgYDVQQDDBdyb2Jv
    dHMuc2FuZnJhbnNva3lvLmVkdTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
    ggIBAO9rzJOOE8cmsIqAJMCrHDxkBAMgZhMsJ863MnWtVz5JIJK6CKI/Nu26tEzo
    kHy3EI9565RwikvauheMsWaTFA4PD/P+s1DtxRCGIcK5x+SoTN7Drn5ZueoJNZRf
    TYuN+gwyhprzrZrYjXpvEVPYuSIeUqK5XGrTyFA2uGj9wY3f9IF4rd7JT0ewRb1U
    8OcR7xQbXKGjkY4iJE1TyfmIsBZboKaG/aYa9KbnWyTkDssaELWUIKrjwwuPgVgS
    vlAYmo12MlsGEzkO9z78jvFmhUOsaEldM8Ua2AhOKW0oSYgauVuro/Ap/o5zn8PD
    IDapl9g+5vjN2LucqX2a9utoFvxSKXT4NvfpL9fJvzdBNMM4xpqtHIkV0fkiMbWk
    EW2FFlOXKnIJV8wT4a9iduuIDMg8O7oc+gt9pG9MHTWthXm4S29DARTqfZ48bW77
    z8RrEURV03o05b/twuAJSRyyOCUi61yMo3YNytebjY2W3Pxqpq+YmT5qhqBZDLlT
    LMptuFdISv6SQgg7JoFHGMWRXUavMj/sn5qZD4pQyZToHJ2Vtg5W/MI1pKwc3oKD
    6M3/7Gf35r92V/ox6XT7+fnEsAH8AtQiZJkEbvzJ5lpUihSIaV3a/S+jnk7Lw8Tp
    vjtpfjOg+wBblc38Oa9tk2WdXwYDbnvbeL26WmyHwQTUBi1jAgMBAAGjUDBOMB0G
    A1UdDgQWBBToPRmTBQEF5F5LcPiUI5qBNPBU+DAfBgNVHSMEGDAWgBToPRmTBQEF
    5F5LcPiUI5qBNPBU+DAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4ICAQCY
    gxM5lufF2lTB9sH0s1E1VTERv37qoapNP+aw06oZkAD67QOTXFzbsM3JU1diY6rV
    Y0g9CLzRO7gZY+kmi1WWnsYiMMSIGjIfsB8S+ot43LME+AJXPVeDZQnoZ6KQ/9r+
    71Umi4AKLoZ9dInyUIM3EHg9pg5B0eEINrh4J+OPGtlC3NMiWxdmIkZwzfXa+64Z
    8k5aX5piMTI+9BQSMWw5l7tFT/PISuI8b/Ln4IUBXKA0xkONXVnjPOmS0h7MBoc2
    EipChDKnK+Mtm9GQewOCKdS2nsrCndGkIBnUix4ConUYIoywVzWGMD+9OzKNg76d
    O6A7MxdjEdKhf1JDvklxInntDUDTlSFL4iEFELwyRseoTzj8vJE+cL6h6ClasYQ6
    p0EeL3UpICYerfIvPhohftCivCH3k7Q1BSf0fq73cQ55nrFAHrqqYjD7HBeBS9hn
    3L6bz9Eo6U9cuxX42k3l1N44BmgcDPin0+CRTirEmahUMb3gmvoSZqQ3Cz86GkIg
    7cNJosc9NyevQlU9SX3ptEbv33tZtlB5GwgZ2hiGBTY0C3HaVFjLpQiSS5ygZLgI
    /+AKtah7sTHIAtpUH1ZZEgKPl1Hg6J4x/dBkuk3wxPommNHaYaHREXF+fHMhBrSi
    yH8agBmmECpa21SVnr7vrL+KSqfuF+GxwjSNsSR4SA==
    -----END CERTIFICATE-----
    """

  static let samplePemKey = """
    -----BEGIN RSA PRIVATE KEY-----
    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
    -----END RSA PRIVATE KEY-----
    """

  func testTLSConfig_Defaults() throws {
    let grpcTLSConfig = HTTP2ServerTransport.Posix.Config.TLS.defaults(
      certificateChain: [
        .bytes(Array(Self.samplePemCert.utf8), format: .pem)
      ],
      privateKey: .bytes(Array(Self.samplePemKey.utf8), format: .pem)
    )
    let nioSSLTLSConfig = try TLSConfiguration(grpcTLSConfig)

    XCTAssertEqual(
      nioSSLTLSConfig.certificateChain,
      [
        .certificate(
          try NIOSSLCertificate(
            bytes: Array(Self.samplePemCert.utf8),
            format: .pem
          )
        )
      ]
    )
    XCTAssertEqual(
      nioSSLTLSConfig.privateKey,
      .privateKey(try NIOSSLPrivateKey(bytes: Array(Self.samplePemKey.utf8), format: .pem))
    )
    XCTAssertEqual(nioSSLTLSConfig.minimumTLSVersion, .tlsv12)
    XCTAssertEqual(nioSSLTLSConfig.certificateVerification, .none)
    XCTAssertEqual(nioSSLTLSConfig.trustRoots, .default)
    XCTAssertEqual(nioSSLTLSConfig.applicationProtocols, ["grpc-exp", "h2"])
  }

  func testTLSConfig_mTLS() throws {
    let grpcTLSConfig = HTTP2ServerTransport.Posix.Config.TLS.mTLS(
      certificateChain: [
        .bytes(Array(Self.samplePemCert.utf8), format: .pem)
      ],
      privateKey: .bytes(Array(Self.samplePemKey.utf8), format: .pem)
    )
    let nioSSLTLSConfig = try TLSConfiguration(grpcTLSConfig)

    XCTAssertEqual(
      nioSSLTLSConfig.certificateChain,
      [
        .certificate(
          try NIOSSLCertificate(
            bytes: Array(Self.samplePemCert.utf8),
            format: .pem
          )
        )
      ]
    )
    XCTAssertEqual(
      nioSSLTLSConfig.privateKey,
      .privateKey(try NIOSSLPrivateKey(bytes: Array(Self.samplePemKey.utf8), format: .pem))
    )
    XCTAssertEqual(nioSSLTLSConfig.minimumTLSVersion, .tlsv12)
    XCTAssertEqual(nioSSLTLSConfig.certificateVerification, .noHostnameVerification)
    XCTAssertEqual(nioSSLTLSConfig.trustRoots, .default)
    XCTAssertEqual(nioSSLTLSConfig.applicationProtocols, ["grpc-exp", "h2"])
  }

  func testTLSConfig_FullVerifyClient() throws {
    var grpcTLSConfig = HTTP2ServerTransport.Posix.Config.TLS.defaults(
      certificateChain: [
        .bytes(Array(Self.samplePemCert.utf8), format: .pem)
      ],
      privateKey: .bytes(Array(Self.samplePemKey.utf8), format: .pem)
    )
    grpcTLSConfig.clientCertificateVerification = .fullVerification
    let nioSSLTLSConfig = try TLSConfiguration(grpcTLSConfig)

    XCTAssertEqual(
      nioSSLTLSConfig.certificateChain,
      [
        .certificate(
          try NIOSSLCertificate(
            bytes: Array(Self.samplePemCert.utf8),
            format: .pem
          )
        )
      ]
    )
    XCTAssertEqual(
      nioSSLTLSConfig.privateKey,
      .privateKey(try NIOSSLPrivateKey(bytes: Array(Self.samplePemKey.utf8), format: .pem))
    )
    XCTAssertEqual(nioSSLTLSConfig.minimumTLSVersion, .tlsv12)
    XCTAssertEqual(nioSSLTLSConfig.certificateVerification, .fullVerification)
    XCTAssertEqual(nioSSLTLSConfig.trustRoots, .default)
    XCTAssertEqual(nioSSLTLSConfig.applicationProtocols, ["grpc-exp", "h2"])
  }

  func testTLSConfig_CustomTrustRoots() throws {
    var grpcTLSConfig = HTTP2ServerTransport.Posix.Config.TLS.defaults(
      certificateChain: [
        .bytes(Array(Self.samplePemCert.utf8), format: .pem)
      ],
      privateKey: .bytes(Array(Self.samplePemKey.utf8), format: .pem)
    )
    grpcTLSConfig.trustRoots = .certificates([.bytes(Array(Self.samplePemCert.utf8), format: .pem)])
    let nioSSLTLSConfig = try TLSConfiguration(grpcTLSConfig)

    XCTAssertEqual(
      nioSSLTLSConfig.certificateChain,
      [
        .certificate(
          try NIOSSLCertificate(
            bytes: Array(Self.samplePemCert.utf8),
            format: .pem
          )
        )
      ]
    )
    XCTAssertEqual(
      nioSSLTLSConfig.privateKey,
      .privateKey(try NIOSSLPrivateKey(bytes: Array(Self.samplePemKey.utf8), format: .pem))
    )
    XCTAssertEqual(nioSSLTLSConfig.minimumTLSVersion, .tlsv12)
    XCTAssertEqual(nioSSLTLSConfig.certificateVerification, .none)
    XCTAssertEqual(
      nioSSLTLSConfig.trustRoots,
      .certificates(try NIOSSLCertificate.fromPEMBytes(Array(Self.samplePemCert.utf8)))
    )
    XCTAssertEqual(nioSSLTLSConfig.applicationProtocols, ["grpc-exp", "h2"])
  }
  #endif
}
