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
import SwiftGRPCNIO
import SwiftGRPCNIOSampleData
import NIO
import NIOSSL
import XCTest

class NIOClientTLSFailureTests: XCTestCase {
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
  var server: GRPCServer!
  var port: Int!

  func makeClientConnection(
    configuration: TLSConfiguration,
    hostOverride: String? = SampleCertificate.server.commonName
  ) throws -> EventLoopFuture<GRPCClientConnection> {
    return try GRPCClientConnection.start(
      host: "localhost",
      port: self.port,
      eventLoopGroup: self.clientEventLoopGroup,
      tls: .custom(try NIOSSLContext(configuration: configuration)),
      hostOverride: hostOverride)
  }

  func makeClientConnectionExpectation() -> XCTestExpectation {
    return self.expectation(description: "EventLoopFuture<GRPCClientConnection> resolved")
  }

  override func setUp() {
    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! GRPCServer.start(
      hostname: "localhost",
      port: 0,
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [EchoProviderNIO()],
      errorDelegate: nil,
      tls: .custom(try NIOSSLContext(configuration: defaultServerTLSConfiguration))
    ).wait()

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
    var configuration = defaultClientTLSConfiguration
    configuration.applicationProtocols = ["not-h2", "not-grpc-ext"]

    let connection = try self.makeClientConnection(configuration: configuration)
    let connectionExpectation = self.makeClientConnectionExpectation()

    connection.assertError(fulfill: connectionExpectation) { error in
      let clientError = (error as? GRPCError)?.error as? GRPCClientError
      XCTAssertEqual(clientError, .applicationLevelProtocolNegotiationFailed)
    }

    self.wait(for: [connectionExpectation], timeout: self.defaultTestTimeout)
  }

  func testClientConnectionFailsWhenServerIsUnknown() throws {
    var configuration = defaultClientTLSConfiguration
    configuration.trustRoots = .certificates([])

    let connection = try self.makeClientConnection(configuration: configuration)
    let connectionExpectation = self.makeClientConnectionExpectation()

    connection.assertError(fulfill: connectionExpectation) { error in
      guard case .some(.handshakeFailed(.sslError)) = error as? NIOSSLError else {
        XCTFail("Expected NIOSSLError.handshakeFailed(BoringSSL.sslError) but got \(error)")
        return
      }
    }

    self.wait(for: [connectionExpectation], timeout: self.defaultTestTimeout)
  }

  func testClientConnectionFailsWhenHostnameIsNotValid() throws {
    let connection = try self.makeClientConnection(
      configuration: self.defaultClientTLSConfiguration,
      hostOverride: "not-the-server-hostname")

    let connectionExpectation = self.makeClientConnectionExpectation()

    connection.assertError(fulfill: connectionExpectation) { error in
      guard case .some(.unableToValidateCertificate) = error as? NIOSSLError else {
        XCTFail("Expected NIOSSLError.unableToValidateCertificate but got \(error)")
        return
      }
    }

    self.wait(for: [connectionExpectation], timeout: self.defaultTestTimeout)
  }
}
