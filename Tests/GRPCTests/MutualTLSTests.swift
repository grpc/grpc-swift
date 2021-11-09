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
import EchoImplementation
import EchoModel
@testable import GRPC
import GRPCSampleData
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL
import XCTest

class MutualTLSTests: GRPCTestCase {
  enum ExpectedOutcome {
    case success
    case serverError
    case clientError
  }

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!

  override func setUp() {
    super.setUp()
    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.serverEventLoopGroup = nil
    super.tearDown()
  }

  func performTestWith(
    _ serverTLSConfiguration: GRPCTLSConfiguration?,
    _ clientTLSConfiguration: GRPCTLSConfiguration?,
    expect expectedOutcome: ExpectedOutcome
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
    serverErrorExpectation.isInverted = expectedOutcome != .serverError
    serverErrorExpectation.assertForOverFulfill = false
    let serverErrorDelegate = ServerErrorRecordingDelegate(expectation: serverErrorExpectation)
    serverConfiguration.errorDelegate = serverErrorDelegate

    let server = try! Server.start(configuration: serverConfiguration).wait()
    let port = server.channel.localAddress!.port!

    // Setup the client.
    var clientConfiguration = ClientConnection.Configuration.default(
      target: .hostAndPort("localhost", port),
      eventLoopGroup: clientEventLoopGroup
    )
    clientConfiguration.tlsConfiguration = clientTLSConfiguration
    clientConfiguration.connectionBackoff = nil
    clientConfiguration.backgroundActivityLogger = self.clientLogger
    let clientErrorExpectation = self.expectation(description: "client error")
    clientErrorExpectation.isInverted = expectedOutcome == .success
    clientErrorExpectation.assertForOverFulfill = false
    let clientErrorDelegate = ErrorRecordingDelegate(expectation: clientErrorExpectation)
    clientConfiguration.errorDelegate = clientErrorDelegate

    let client = Echo_EchoClient(channel: ClientConnection(configuration: clientConfiguration))

    // Make the call.
    let call = client.get(.with { $0.text = "mumble" })

    // Wait for side effects.
    self.wait(for: [clientErrorExpectation, serverErrorExpectation], timeout: 1)

    switch expectedOutcome {
    case .success:
      // Verify no errors.
      XCTAssert(serverErrorDelegate.errors.isEmpty)
      XCTAssert(clientErrorDelegate.errors.isEmpty)
      // Verify response.
      let response = try call.response.wait()
      XCTAssertEqual(response.text, "Swift echo get: mumble")
      let status = try call.status.wait()
      XCTAssertEqual(status.code, .ok)
    case .serverError:
      // Verify handshake error.
      guard case .handshakeFailed = serverErrorDelegate.errors.first as? NIOSSLError else {
        XCTFail("Expected NIOSSLError.handshakeFailed")
        return
      }
    case .clientError:
      // Verify handshake error.
      guard case .handshakeFailed = clientErrorDelegate.errors.first as? NIOSSLError else {
        XCTFail("Expected NIOSSLError.handshakeFailed")
        return
      }
    }
  }

  func test_ValidClientAndServerCerts_Success() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([SampleCertificate.ca.certificate]),
      certificateVerification: .noHostnameVerification
    )
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.client.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([SampleCertificate.ca.certificate]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(serverTLSConfiguration, clientTLSConfiguration, expect: .success)
  }

  func test_noServerCert_ClientError() throws {
    let clientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.client.certificate)],
      privateKey: .privateKey(SamplePrivateKey.client),
      trustRoots: .certificates([SampleCertificate.ca.certificate]),
      certificateVerification: .fullVerification
    )
    try self.performTestWith(nil, clientTLSConfiguration, expect: .clientError)
  }

  func test_noClientCert_ServerError() throws {
    let serverTLSConfiguration = GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(
      certificateChain: [.certificate(SampleCertificate.server.certificate)],
      privateKey: .privateKey(SamplePrivateKey.server),
      trustRoots: .certificates([SampleCertificate.ca.certificate]),
      certificateVerification: .noHostnameVerification
    )
    try self.performTestWith(serverTLSConfiguration, nil, expect: .serverError)
  }
}
