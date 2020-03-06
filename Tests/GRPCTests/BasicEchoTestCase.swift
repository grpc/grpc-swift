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
import EchoModel
import EchoImplementation
import XCTest

extension Echo_EchoRequest {
  init(text: String) {
    self = .with {
      $0.text = text
    }
  }
}

extension Echo_EchoResponse {
  init(text: String) {
    self = .with {
      $0.text = text
    }
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
  func makeServerTLSConfiguration() -> Server.Configuration.TLS? {
    switch self {
    case .none:
      return nil

    case .anonymousClient, .mutualAuthentication:
      return .init(certificateChain: [.certificate(self.serverCert)],
                   privateKey: .privateKey(SamplePrivateKey.server),
                   trustRoots: .certificates ([self.caCert]))
    }
  }

  func makeClientTLSConfiguration() -> ClientConnection.Configuration.TLS? {
    switch self {
    case .none:
      return nil

    case .anonymousClient:
      return .init(trustRoots: .certificates([self.caCert]))

    case .mutualAuthentication:
      return .init(
        certificateChain: [.certificate(self.clientCert)],
        privateKey: .privateKey(SamplePrivateKey.client),
        trustRoots: .certificates([self.caCert])
      )
    }
  }
}

class EchoTestCaseBase: GRPCTestCase {
  var defaultTestTimeout: TimeInterval = 1.0

  var serverEventLoopGroup: EventLoopGroup!
  var clientEventLoopGroup: EventLoopGroup!

  var transportSecurity: TransportSecurity { return .none }

  var server: Server!
  var client: Echo_EchoClient!
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
      tls: self.transportSecurity.makeClientTLSConfiguration())
  }

  func makeServerConfiguration() throws -> Server.Configuration {
    return .init(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [makeEchoProvider()],
      errorDelegate: self.makeErrorDelegate(),
      tls: self.transportSecurity.makeServerTLSConfiguration())
  }

  func makeServer() throws -> Server {
    return try Server.start(configuration: self.makeServerConfiguration()).wait()
  }

  func makeClientConnection(port: Int) throws -> ClientConnection {
    return try ClientConnection(configuration: self.makeClientConfiguration(port: port))
  }

  func makeEchoProvider() -> Echo_EchoProvider { return EchoProvider() }

  func makeErrorDelegate() -> ServerErrorDelegate? { return nil }

  func makeEchoClient(port: Int) throws -> Echo_EchoClient {
    return Echo_EchoClient(channel: try self.makeClientConnection(port: port))
  }

  override func setUp() {
    super.setUp()
    self.serverEventLoopGroup = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference)
    self.server = try! self.makeServer()

    self.port = self.server.channel.localAddress!.port!

    self.clientEventLoopGroup = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference)
    self.client = try! self.makeEchoClient(port: self.port)
  }

  override func tearDown() {
    // Some tests close the channel, so would throw here if called twice.
    try? self.client.channel.close().wait()
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
