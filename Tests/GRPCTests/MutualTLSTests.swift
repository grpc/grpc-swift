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
#if canImport(NIOSSL)
import EchoImplementation
import EchoModel
@testable import GRPC
import GRPCSampleData
import NIOCore
import NIOPosix
import NIOSSL
import XCTest

class MutualTLSTests: GRPCTestCase {
  enum ExpectedClientError {
    case handshakeError
    case alertCertRequired
    case dropped
  }

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!
  var channel: GRPCChannel?
  var server: Server?

  override func setUp() {
    super.setUp()
    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel?.close().wait())
    XCTAssertNoThrow(try self.server?.close().wait())
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    super.tearDown()
  }

  func performTestWith(
    _ serverTLSConfiguration: GRPCTLSConfiguration?,
    _ clientTLSConfiguration: GRPCTLSConfiguration?,
    expectServerHandshakeError: Bool,
    expectedClientError: ExpectedClientError?
  ) throws {
    // Setup the server.
    var serverConfiguration = Server.Configuration.default(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [EchoProvider()]
    )
    serverConfiguration.tlsConfiguration = serverTLSConfiguration
    serverConfiguration.logger = self.serverLogger
    let serverErrorExpectation = self.expectation(description: "server error")
    serverErrorExpectation.isInverted = !expectServerHandshakeError
    serverErrorExpectation.assertForOverFulfill = false
    let serverErrorDelegate = ServerErrorRecordingDelegate(expectation: serverErrorExpectation)
    serverConfiguration.errorDelegate = serverErrorDelegate

    self.server = try! Server.start(configuration: serverConfiguration).wait()

    let port = self.server!.channel.localAddress!.port!

    // Setup the client.
    var clientConfiguration = ClientConnection.Configuration.default(
      target: .hostAndPort("localhost", port),
      eventLoopGroup: self.clientEventLoopGroup
    )
    clientConfiguration.tlsConfiguration = clientTLSConfiguration
    clientConfiguration.connectionBackoff = nil
    clientConfiguration.backgroundActivityLogger = self.clientLogger
    let clientErrorExpectation = self.expectation(description: "client error")
    switch expectedClientError {
    case .none:
      clientErrorExpectation.isInverted = true
    case .handshakeError, .alertCertRequired:
      // After the SSL error, the connection being closed also presents as an error.
      clientErrorExpectation.expectedFulfillmentCount = 2
    case .dropped:
      clientErrorExpectation.expectedFulfillmentCount = 1
    }
    let clientErrorDelegate = ErrorRecordingDelegate(expectation: clientErrorExpectation)
    clientConfiguration.errorDelegate = clientErrorDelegate

    self.channel = ClientConnection(configuration: clientConfiguration)
    let client = Echo_EchoNIOClient(channel: channel!)

    // Make the call.
    let call = client.get(.with { $0.text = "mumble" })

    // Wait for side effects.
    self.wait(for: [clientErrorExpectation, serverErrorExpectation], timeout: 10)

    if !expectServerHandshakeError {
      XCTAssert(
        serverErrorDelegate.errors.isEmpty,
        "Unexpected server errors: \(serverErrorDelegate.errors)"
      )
    } else if case .handshakeFailed = serverErrorDelegate.errors.first as? NIOSSLError {
      // This is the expected error.
    } else {
      XCTFail(
        "Expected NIOSSLError.handshakeFailed, actual error(s): \(serverErrorDelegate.errors)"
      )
    }

    switch expectedClientError {
    case .none:
      XCTAssert(
        clientErrorDelegate.errors.isEmpty,
        "Unexpected client errors: \(clientErrorDelegate.errors)"
      )
    case .some(.handshakeError):
      if case .handshakeFailed = clientErrorDelegate.errors.first as? NIOSSLError {
        // This is the expected error.
      } else {
        XCTFail(
          "Expected NIOSSLError.handshakeFailed, actual error(s): \(clientErrorDelegate.errors)"
        )
      }
    case .some(.alertCertRequired):
      if let error = clientErrorDelegate.errors.first, error is BoringSSLError {
        // This is the expected error when client receives TLSV1_ALERT_CERTIFICATE_REQUIRED.
      } else {
        XCTFail("Expected BoringSSLError, actual error(s): \(clientErrorDelegate.errors)")
      }
    case .some(.dropped):
      if let error = clientErrorDelegate.errors.first as? GRPCStatus, error.code == .unavailable {
        // This is the expected error when client closes the connection.
      } else {
        XCTFail("Expected BoringSSLError, actual error(s): \(clientErrorDelegate.errors)")
      }
    }

    if !expectServerHandshakeError, expectedClientError == nil {
      // Verify response.
      let response = try call.response.wait()
      XCTAssertEqual(response.text, "Swift echo get: mumble")
      let status = try call.status.wait()
      XCTAssertEqual(status.code, .ok)
    }
  }

  func test_trustedClientAndServerCerts_success() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .noHostnameVerification
    )
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.clientSignedByOtherCA.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(
      serverTLSConfiguration,
      clientTLSConfiguration,
      expectServerHandshakeError: false,
      expectedClientError: nil
    )
  }

  func test_untrustedServerCert_clientError() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .noHostnameVerification
    )
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.clientSignedByOtherCA.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([
        SampleCertificate.otherCA.certificate
      ]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(
      serverTLSConfiguration,
      clientTLSConfiguration,
      expectServerHandshakeError: true,
      expectedClientError: .handshakeError
    )
  }

  func test_untrustedClientCert_serverError() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate
      ]),
      certificateVerification: .noHostnameVerification
    )
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.clientSignedByOtherCA.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(
      serverTLSConfiguration,
      clientTLSConfiguration,
      expectServerHandshakeError: true,
      expectedClientError: .alertCertRequired
    )
  }

  func test_plaintextServer_clientError() throws {
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.clientSignedByOtherCA.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(
      nil,
      clientTLSConfiguration,
      expectServerHandshakeError: false,
      expectedClientError: .handshakeError
    )
  }

  func test_plaintextClient_serverError() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([
        SampleCertificate.ca.certificate,
        SampleCertificate.otherCA.certificate,
      ]),
      certificateVerification: .noHostnameVerification
    )
    try self.performTestWith(
      serverTLSConfiguration,
      nil,
      expectServerHandshakeError: true,
      expectedClientError: .dropped
    )
  }
}

#endif  // canImport(NIOSSL)
