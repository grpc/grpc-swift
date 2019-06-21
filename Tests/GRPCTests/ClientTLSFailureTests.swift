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
import Foundation
import GRPC
import GRPCSampleData
import NIO
import NIOSSL
import XCTest

class ErrorRecordingDelegate: ClientErrorDelegate {
  var errors: [Error] = []
  var expectation: XCTestExpectation

  init(expectation: XCTestExpectation) {
    self.expectation = expectation
  }

  func didCatchError(_ error: Error, file: StaticString, line: Int) {
    self.errors.append(error)
    self.expectation.fulfill()
  }
}

class ClientTLSFailureTests: XCTestCase {
  let defaultServerTLSConfiguration = TLSConfiguration.forServer(
    certificateChain: [.certificate(SampleCertificate.server.certificate)],
    privateKey: .privateKey(SamplePrivateKey.server),
    applicationProtocols: GRPCApplicationProtocolIdentifier.allCases.map { $0.rawValue })

  let defaultClientTLSConfiguration = TLSConfiguration.forClient(
    trustRoots: .certificates([SampleCertificate.ca.certificate]),
    certificateChain: [.certificate(SampleCertificate.client.certificate)],
    privateKey: .privateKey(SamplePrivateKey.client),
    applicationProtocols: GRPCApplicationProtocolIdentifier.allCases.map { $0.rawValue })

  var defaultTestTimeout: TimeInterval = 1.0

  var clientEventLoopGroup: EventLoopGroup!
  var serverEventLoopGroup: EventLoopGroup!
  var server: Server!
  var port: Int!

  func makeClientConfiguration(
    tls: TLSConfiguration,
    hostOverride: String? = SampleCertificate.server.commonName
  ) throws -> ClientConnection.Configuration {
    return ClientConnection.Configuration(
      target: .hostAndPort("localhost", self.port),
      eventLoopGroup: self.clientEventLoopGroup,
      tlsConfiguration: try .init(
        sslContext: NIOSSLContext(configuration: tls),
        hostnameOverride: hostOverride
      )
    )
  }

  func makeClientTLSConfiguration(
    tls: TLSConfiguration,
    hostOverride: String? = SampleCertificate.server.commonName
  ) throws -> ClientConnection.TLSConfiguration {
    let context = try NIOSSLContext(configuration: tls)
    return .init(sslContext: context, hostnameOverride: hostOverride)
  }

  func makeClientConnectionExpectation() -> XCTestExpectation {
    return self.expectation(description: "EventLoopFuture<ClientConnection> resolved")
  }

  override func setUp() {
    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let sslContext = try! NIOSSLContext(configuration: self.defaultServerTLSConfiguration)

    let configuration = Server.Configuration(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [EchoProvider()],
      errorDelegate: nil,
      tlsConfiguration: .init(sslContext: sslContext))

    self.server = try! Server.start(configuration: configuration).wait()

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
  }

  func testClientConnectionFailsWhenProtocolCanNotBeNegotiated() throws {
    let shutdownExpectation = self.expectation(description: "client shutdown")
    let errorExpectation = self.expectation(description: "error")

    var tls = defaultClientTLSConfiguration
    tls.applicationProtocols = ["not-h2", "not-grpc-ext"]
    var configuration = try self.makeClientConfiguration(tls: tls)

    let errorRecorder = ErrorRecordingDelegate(expectation: errorExpectation)
    configuration.errorDelegate = errorRecorder

    let connection = ClientConnection(configuration: configuration)
    connection.connectivity.onNext(state: .shutdown) {
      shutdownExpectation.fulfill()
    }

    self.wait(for: [shutdownExpectation, errorExpectation], timeout: self.defaultTestTimeout)

    let clientErrors = errorRecorder.errors.compactMap { $0 as? GRPCClientError }
    XCTAssertEqual(clientErrors, [.applicationLevelProtocolNegotiationFailed])
  }

  func testClientConnectionFailsWhenServerIsUnknown() throws {
    let shutdownExpectation = self.expectation(description: "client shutdown")
    let errorExpectation = self.expectation(description: "error")

    var tls = defaultClientTLSConfiguration
    tls.trustRoots = .certificates([])
    var configuration = try self.makeClientConfiguration(tls: tls)

    let errorRecorder = ErrorRecordingDelegate(expectation: errorExpectation)
    configuration.errorDelegate = errorRecorder

    let connection = ClientConnection(configuration: configuration)
    connection.connectivity.onNext(state: .shutdown) {
      shutdownExpectation.fulfill()
    }

    self.wait(for: [shutdownExpectation, errorExpectation], timeout: self.defaultTestTimeout)

    if let nioSSLError = errorRecorder.errors.first as? NIOSSLError,
      case .handshakeFailed(.sslError) = nioSSLError {
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLError.handshakeFailed(BoringSSL.sslError)")
    }
  }

  func testClientConnectionFailsWhenHostnameIsNotValid() throws {
    let shutdownExpectation = self.expectation(description: "client shutdown")
    let errorExpectation = self.expectation(description: "error")

    var configuration = try self.makeClientConfiguration(
      tls: self.defaultClientTLSConfiguration,
      hostOverride: "not-the-server-hostname"
    )

    let errorRecorder = ErrorRecordingDelegate(expectation: errorExpectation)
    configuration.errorDelegate = errorRecorder

    let connection = ClientConnection(configuration: configuration)
    connection.connectivity.onNext(state: .shutdown) {
      shutdownExpectation.fulfill()
    }

    self.wait(for: [shutdownExpectation, errorExpectation], timeout: self.defaultTestTimeout)

    if let nioSSLError = errorRecorder.errors.first as? NIOSSLError,
      case .unableToValidateCertificate = nioSSLError {
      // Expected case.
    } else {
      XCTFail("Expected NIOSSLError.unableToValidateCertificate")
    }
  }
}
