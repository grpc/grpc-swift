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
@testable import SwiftGRPCNIO
import SwiftGRPCNIOSampleData
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
  func makeServerTLS() throws -> GRPCServer.TLSMode {
    return try makeServerTLSConfiguration().map { .custom(try NIOSSLContext(configuration: $0)) } ?? .none
  }

  func makeServerTLSConfiguration() throws -> TLSConfiguration? {
    switch self {
    case .none:
      return nil

    case .anonymousClient, .mutualAuthentication:
      return .forServer(certificateChain: [.certificate(self.serverCert)],
                        privateKey: .privateKey(SamplePrivateKey.server), 
                        trustRoots: .certificates ([self.caCert]))
    }
  }

  func makeClientTLS() throws -> GRPCClientConnection.TLSMode {
    return try makeClientTLSConfiguration().map { .custom(try NIOSSLContext(configuration: $0)) } ?? .none
  }

  func makeClientTLSConfiguration() throws -> TLSConfiguration? {
    switch self {
    case .none:
      return nil

    case .anonymousClient:
      return .forClient(certificateVerification: .noHostnameVerification,
                        trustRoots: .certificates([self.caCert]))

    case .mutualAuthentication:
      return .forClient(certificateVerification: .noHostnameVerification,
                        trustRoots: .certificates([self.caCert]),
                        certificateChain: [.certificate(self.clientCert)],
                        privateKey: .privateKey(SamplePrivateKey.client))
    }
  }
}

class NIOEchoTestCaseBase: XCTestCase {
  var defaultTestTimeout: TimeInterval = 1.0

  let serverEventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  let clientEventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

  var transportSecurity: TransportSecurity {
    return .none
  }

  var server: GRPCServer!
  var client: Echo_EchoService_NIOClient!

  func makeServer() throws -> GRPCServer {
    return try GRPCServer.start(
      hostname: "localhost",
      port: 5050,
      eventLoopGroup: self.serverEventLoopGroup,
      serviceProviders: [makeEchoProvider()],
      tls: try self.transportSecurity.makeServerTLS()
    ).wait()
  }

  func makeClientConnection() throws -> GRPCClientConnection {
    return try GRPCClientConnection.start(
      host: "localhost",
      port: 5050,
      eventLoopGroup: self.clientEventLoopGroup,
      tls: try self.transportSecurity.makeClientTLS()
    ).wait()
  }

  func makeEchoProvider() -> Echo_EchoProvider_NIO {
    return EchoProviderNIO()
  }

  func makeEchoClient() throws -> Echo_EchoService_NIOClient {
    return Echo_EchoService_NIOClient(connection: try self.makeClientConnection())
  }

  override func setUp() {
    super.setUp()
    self.server = try! self.makeServer()
    self.client = try! self.makeEchoClient()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.connection.close().wait())
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.client = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.server = nil

    super.tearDown()
  }
}
