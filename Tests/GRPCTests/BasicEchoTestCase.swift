/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import Dispatch
import Foundation
import NIO
import NIOSSL
import GRPC
import GRPCSampleData
import XCTest

extension Echo_EchoRequest {
  init(text: String) {
    self.text = text
  }
}

extension Echo_EchoResponse {
  init(text: String) {
    self.text = text
  }
}

enum TransportSecurity {
  case none
  case anonymousClient
  case mutualAuthentication
}

extension TransportSecurity {
  var caCert: NIOSSLCertificate {
    let cert = SampleCertificate.ca
    cert.assertNotExpired()
    return cert.certificate
  }

  var clientCert: NIOSSLCertificate {
    let cert = SampleCertificate.client
    cert.assertNotExpired()
    return cert.certificate
  }

  var serverCert: NIOSSLCertificate {
    let cert = SampleCertificate.server
    cert.assertNotExpired()
    return cert.certificate
  }
}

extension TransportSecurity {
  func makeServerConfiguration() throws -> Server.TLSConfiguration? {
    guard let config = try self.makeServerTLSConfiguration() else {
      return nil
    }

    let context = try NIOSSLContext(configuration: config)
    return .init(sslContext: context)
  }

  func makeServerTLSConfiguration() throws -> TLSConfiguration? {
    switch self {
    case .none:
      return nil

    case .anonymousClient, .mutualAuthentication:
      return .forServer(certificateChain: [.certificate(self.serverCert)],
                        privateKey: .privateKey(SamplePrivateKey.server),
                        trustRoots: .certificates ([self.caCert]),
                        applicationProtocols: GRPCApplicationProtocolIdentifier.allCases.map { $0.rawValue })
    }
  }

  func makeClientConfiguration() throws -> ClientConnection.TLSConfiguration? {
    guard let config = try self.makeClientTLSConfiguration() else {
      return nil
    }

    let context = try NIOSSLContext(configuration: config)
    return ClientConnection.TLSConfiguration(sslContext: context)
  }

  func makeClientTLSConfiguration() throws -> TLSConfiguration? {
    switch self {
    case .none:
      return nil

    case .anonymousClient:
      return .forClient(certificateVerification: .noHostnameVerification,
                        trustRoots: .certificates([self.caCert]),
                        applicationProtocols: GRPCApplicationProtocolIdentifier.allCases.map { $0.rawValue })

    case .mutualAuthentication:
      return .forClient(certificateVerification: .noHostnameVerification,
                        trustRoots: .certificates([self.caCert]),
                        certificateChain: [.certificate(self.clientCert)],
                        privateKey: .privateKey(SamplePrivateKey.client),
                        applicationProtocols: GRPCApplicationProtocolIdentifier.allCases.map { $0.rawValue })
    }
  }
}

class EchoTestCaseBase: XCTestCase {
  var defaultTestTimeout: TimeInterval = 1.0

  var serverEventLoopGroup: EventLoopGroup!
  var clientEventLoopGroup: EventLoopGroup!

  var transportSecurity: TransportSecurity { return .none }

  var server: Server!
  var client: Echo_EchoServiceClient!
  var port: Int!

  // Prefer POSIX: subclasses can override this and add availability checks to ensure NIOTS
  // variants run where possible.
  var networkPreference: NetworkPreference {
    return .userDefined(.posix)
  }

  func makeClientConfiguration(port: Int) throws -> ClientConnection.Configuration {
    return .init(
      target: .hostAndPort("localhost", port),
      eventLoopGroup: self.clientEventLoopGroup,
      tlsConfiguration: try self.transportSecurity.makeClientConfiguration())
  }

  func makeServerConfiguration() throws -> Server.Configuration {
    return .init(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [makeEchoProvider()],
      errorDelegate: self.makeErrorDelegate(),
      tlsConfiguration: try self.transportSecurity.makeServerConfiguration())
  }

  func makeServer() throws -> Server {
    return try Server.start(configuration: self.makeServerConfiguration()).wait()
  }

  func makeClientConnection(port: Int) throws -> ClientConnection {
    return try ClientConnection.start(self.makeClientConfiguration(port: port)).wait()
  }

  func makeEchoProvider() -> Echo_EchoProvider { return EchoProvider() }

  func makeErrorDelegate() -> ServerErrorDelegate? { return nil }

  func makeEchoClient(port: Int) throws -> Echo_EchoServiceClient {
    return Echo_EchoServiceClient(connection: try self.makeClientConnection(port: port))
  }

  override func setUp() {
    super.setUp()
    self.serverEventLoopGroup = GRPCNIO.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference)
    self.server = try! self.makeServer()

    self.port = self.server.channel.localAddress!.port!

    self.clientEventLoopGroup = GRPCNIO.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference)
    self.client = try! self.makeEchoClient(port: self.port)
  }

  override func tearDown() {
    // Some tests close the channel, so would throw here if called twice.
    try? self.client.connection.close().wait()

    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.client = nil
    self.clientEventLoopGroup = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.server = nil
    self.serverEventLoopGroup = nil
    self.port = nil

    super.tearDown()
  }
}

extension EchoTestCaseBase {
  func makeExpectation(description: String, expectedFulfillmentCount: Int = 1, assertForOverFulfill: Bool = true) -> XCTestExpectation {
    let expectation = self.expectation(description: description)
    expectation.expectedFulfillmentCount = expectedFulfillmentCount
    expectation.assertForOverFulfill = assertForOverFulfill
    return expectation
  }

  func makeStatusExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return makeExpectation(description: "Expecting status received",
                           expectedFulfillmentCount: expectedFulfillmentCount)
  }

  func makeResponseExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return makeExpectation(description: "Expecting \(expectedFulfillmentCount) response(s)",
      expectedFulfillmentCount: expectedFulfillmentCount)
  }

  func makeRequestExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return makeExpectation(
      description: "Expecting \(expectedFulfillmentCount) request(s) to have been sent",
      expectedFulfillmentCount: expectedFulfillmentCount)
  }

  func makeInitialMetadataExpectation() -> XCTestExpectation {
    return makeExpectation(description: "Expecting initial metadata")
  }
}
