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
@testable import GRPC
import GRPCSampleData
import EchoModel
import EchoImplementation
import Logging
import NIO
import NIOSSL
import XCTest

class ErrorRecordingDelegate: ClientErrorDelegate {
  var errors: [Error] = []
  var expectation: XCTestExpectation

  init(expectation: XCTestExpectation) {
    self.expectation = expectation
  }

  func didCatchError(_ error: Error, logger: Logger, file: StaticString, line: Int) {
    self.errors.append(error)
    self.expectation.fulfill()
  }
}

class ClientTLSFailureTests: GRPCTestCase {
  let defaultServerTLSConfiguration = Server.Configuration.TLS(
    certificateChain: [.certificate(SampleCertificate.server.certificate)],
    privateKey: .privateKey(SamplePrivateKey.server))

  let defaultClientTLSConfiguration = ClientConnection.Configuration.TLS(
    certificateChain: [.certificate(SampleCertificate.client.certificate)],
    privateKey: .privateKey(SamplePrivateKey.client),
    trustRoots: .certificates([SampleCertificate.ca.certificate]),
    hostnameOverride: SampleCertificate.server.commonName)

  var defaultTestTimeout: TimeInterval = 1.0

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!
  var server: Server!
  var port: Int!

  func makeClientConfiguration(
    tls: ClientConnection.Configuration.TLS
  ) -> ClientConnection.Configuration {
    return .init(
      target: .hostAndPort("localhost", self.port),
      eventLoopGroup: self.clientEventLoopGroup,
      tls: tls,
      // No need to retry connecting.
      connectionBackoff: nil,
      backgroundActivityLogger: self.clientLogger
    )
  }

  func makeClientConnectionExpectation() -> XCTestExpectation {
    return self.expectation(description: "EventLoopFuture<ClientConnection> resolved")
  }

  override func setUp() {
    super.setUp()

    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.server = try! Server.secure(
      group: self.serverEventLoopGroup,
      certificateChain: [SampleCertificate.server.certificate],
      privateKey: SamplePrivateKey.server
    ).withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()

    self.port = self.server.channel.localAddress?.port

    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    // Delay the client connection creation until the test.
  }

  override func tearDown() {
    self.port = nil

    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.server = nil
    self.serverEventLoopGroup = nil

    super.tearDown()
  }

  func testClientConnectionFailsWhenServerIsUnknown() throws {
    let errorExpectation = self.expectation(description: "error")
    // 2 errors: one for the failed handshake, and another for failing the ready-channel promise
    // (because the handshake failed).
    errorExpectation.expectedFulfillmentCount = 2

    var tls = self.defaultClientTLSConfiguration
    tls.trustRoots = .certificates([])
    var configuration = self.makeClientConfiguration(tls: tls)

    let errorRecorder = ErrorRecordingDelegate(expectation: errorExpectation)
    configuration.errorDelegate = errorRecorder

    let stateChangeDelegate = RecordingConnectivityDelegate()
    stateChangeDelegate.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .shutdown)
      ])
    }
    configuration.connectivityStateDelegate = stateChangeDelegate

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: ClientConnection(configuration: configuration))
    _ = echo.get(.with { $0.text = "foo" })

    self.wait(for: [errorExpectation], timeout: self.defaultTestTimeout)
    stateChangeDelegate.waitForExpectedChanges(timeout: .seconds(5))

    if let nioSSLError = errorRecorder.errors.first as? NIOSSLError,
      case .handshakeFailed(.sslError) = nioSSLError {
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLError.handshakeFailed(BoringSSL.sslError)")
    }
  }

  func testClientConnectionFailsWhenHostnameIsNotValid() throws {
    let errorExpectation = self.expectation(description: "error")
    // 2 errors: one for the failed handshake, and another for failing the ready-channel promise
    // (because the handshake failed).
    errorExpectation.expectedFulfillmentCount = 2

    var tls = self.defaultClientTLSConfiguration
    tls.hostnameOverride = "not-the-server-hostname"

    var configuration = self.makeClientConfiguration(tls: tls)
    let errorRecorder = ErrorRecordingDelegate(expectation: errorExpectation)
    configuration.errorDelegate = errorRecorder

    let stateChangeDelegate = RecordingConnectivityDelegate()
    stateChangeDelegate.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .shutdown)
      ])
    }
    configuration.connectivityStateDelegate = stateChangeDelegate

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: ClientConnection(configuration: configuration))
    _ = echo.get(.with { $0.text = "foo" })

    self.wait(for: [errorExpectation], timeout: self.defaultTestTimeout)
    stateChangeDelegate.waitForExpectedChanges(timeout: .seconds(5))

    if let nioSSLError = errorRecorder.errors.first as? NIOSSLExtraError {
      XCTAssertEqual(nioSSLError, .failedToValidateHostname)
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLExtraError.failedToValidateHostname")
    }
  }
}
