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
@testable import GRPC
import GRPCSampleData
import EchoModel
import EchoImplementation
import Logging
import NIO
import NIOSSL
import XCTest

class ServerErrorRecordingDelegate: ServerErrorDelegate {
  var errors: [Error] = []
  var expectation: XCTestExpectation

  init(expectation: XCTestExpectation) {
    self.expectation = expectation
  }

  func observeLibraryError(_ error: Error) {
    self.errors.append(error)
    self.expectation.fulfill()
  }
}

class ServerTLSErrorTests: GRPCTestCase {
  let defaultClientTLSConfiguration = ClientConnection.Configuration.TLS(
    certificateChain: [.certificate(SampleCertificate.client.certificate)],
    privateKey: .privateKey(SamplePrivateKey.client),
    trustRoots: .certificates([SampleCertificate.ca.certificate]),
    hostnameOverride: SampleCertificate.server.commonName)

  var defaultTestTimeout: TimeInterval = 1.0

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!

  func makeClientConfiguration(
    tls: ClientConnection.Configuration.TLS,
    port: Int
  ) -> ClientConnection.Configuration {
    return .init(
      target: .hostAndPort("localhost", port),
      eventLoopGroup: self.clientEventLoopGroup,
      tls: tls,
      // No need to retry connecting.
      connectionBackoff: nil
    )
  }

  func makeClientConnectionExpectation() -> XCTestExpectation {
    return self.expectation(description: "EventLoopFuture<ClientConnection> resolved")
  }

  override func setUp() {
    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.serverEventLoopGroup = nil
  }

  func testErrorIsLoggedWhenSSLContextErrors() throws {
    let clientShutdownExpectation = self.expectation(description: "client shutdown")
    let errorExpectation = self.expectation(description: "error")
    let errorDelegate = ServerErrorRecordingDelegate(expectation: errorExpectation)

    let server = try! Server.secure(
      group: self.serverEventLoopGroup,
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
    tls.trustRoots = .certificates([SampleCertificate.exampleServerWithExplicitCurve.certificate])
    var configuration = self.makeClientConfiguration(tls: tls, port: port)

    let stateChangeDelegate = ConnectivityStateCollectionDelegate(shutdown: clientShutdownExpectation)
    configuration.connectivityStateDelegate = stateChangeDelegate

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: ClientConnection(configuration: configuration))
    defer {
      XCTAssertNoThrow(try echo.channel.close().wait())
    }
    _ = echo.get(.with { $0.text = "foo" })

    self.wait(for: [clientShutdownExpectation, errorExpectation], timeout: self.defaultTestTimeout)

    if let nioSSLError = errorDelegate.errors.first as? NIOSSLError,
      case .failedToLoadCertificate = nioSSLError {
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLError.handshakeFailed(BoringSSL.sslError)")
    }
  }
}
