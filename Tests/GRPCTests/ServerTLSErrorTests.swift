/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import XCTest

class ServerTLSErrorTests: GRPCTestCase {
  let defaultClientTLSConfiguration = GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(
    certificateChain: [.certificate(SampleCertificate.client.certificate)],
    privateKey: .privateKey(SamplePrivateKey.client),
    trustRoots: .certificates([SampleCertificate.ca.certificate]),
    hostnameOverride: SampleCertificate.server.commonName
  )

  var defaultTestTimeout: TimeInterval = 1.0

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!

  func makeClientConfiguration(
    tls: GRPCTLSConfiguration,
    port: Int
  ) -> ClientConnection.Configuration {
    var configuration = ClientConnection.Configuration.default(
      target: .hostAndPort("localhost", port),
      eventLoopGroup: self.clientEventLoopGroup
    )

    configuration.tlsConfiguration = tls
    // No need to retry connecting.
    configuration.connectionBackoff = nil

    return configuration
  }

  func makeClientConnectionExpectation() -> XCTestExpectation {
    return self.expectation(description: "EventLoopFuture<ClientConnection> resolved")
  }

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

  func testErrorIsLoggedWhenSSLContextErrors() throws {
    let errorExpectation = self.expectation(description: "error")
    let errorDelegate = ServerErrorRecordingDelegate(expectation: errorExpectation)

    let server = try! Server.usingTLSBackedByNIOSSL(
      on: self.serverEventLoopGroup,
      certificateChain: [SampleCertificate.exampleServerWithExplicitCurve.certificate],
      privateKey: SamplePrivateKey.exampleServerWithExplicitCurve
    ).withServiceProviders([EchoProvider()])
      .withErrorDelegate(errorDelegate)
      .bind(host: "localhost", port: 0)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    let port = server.channel.localAddress!.port!

    var tls = self.defaultClientTLSConfiguration
    tls.updateNIOTrustRoots(
      to: .certificates([SampleCertificate.exampleServerWithExplicitCurve.certificate])
    )

    var configuration = self.makeClientConfiguration(tls: tls, port: port)

    let stateChangeDelegate = RecordingConnectivityDelegate()
    stateChangeDelegate.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .shutdown),
      ])
    }

    configuration.connectivityStateDelegate = stateChangeDelegate

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: ClientConnection(configuration: configuration))
    defer {
      XCTAssertNoThrow(try echo.channel.close().wait())
    }
    _ = echo.get(.with { $0.text = "foo" })

    self.wait(for: [errorExpectation], timeout: self.defaultTestTimeout)
    stateChangeDelegate.waitForExpectedChanges(timeout: .seconds(1))

    if let nioSSLError = errorDelegate.errors.first as? NIOSSLError,
      case .failedToLoadCertificate = nioSSLError {
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLError.handshakeFailed(BoringSSL.sslError)")
    }
  }
}

#endif // canImport(NIOSSL)
