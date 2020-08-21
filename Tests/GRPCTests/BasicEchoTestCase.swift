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
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCSampleData
import NIO
import NIOSSL
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

class EchoTestCaseBase: GRPCTestCase {
  // Things can be slow when running under TSAN; bias towards a really long timeout so that we know
  // for sure a test is wedged rather than simply slow.
  var defaultTestTimeout: TimeInterval = 120.0

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

  func connectionBuilder() -> ClientConnection.Builder {
    switch self.transportSecurity {
    case .none:
      return ClientConnection.insecure(group: self.clientEventLoopGroup)

    case .anonymousClient:
      return ClientConnection.secure(group: self.clientEventLoopGroup)
        .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))

    case .mutualAuthentication:
      return ClientConnection.secure(group: self.clientEventLoopGroup)
        .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
        .withTLS(certificateChain: [SampleCertificate.client.certificate])
        .withTLS(privateKey: SamplePrivateKey.client)
    }
  }

  func serverBuilder() -> Server.Builder {
    switch self.transportSecurity {
    case .none:
      return Server.insecure(group: self.serverEventLoopGroup)

    case .anonymousClient, .mutualAuthentication:
      return Server.secure(
        group: self.serverEventLoopGroup,
        certificateChain: [SampleCertificate.server.certificate],
        privateKey: SamplePrivateKey.server
      ).withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
    }
  }

  func makeServer() throws -> Server {
    return try self.serverBuilder()
      .withErrorDelegate(self.makeErrorDelegate())
      .withServiceProviders([self.makeEchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()
  }

  func makeClientConnection(port: Int) throws -> ClientConnection {
    return self.connectionBuilder()
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)
  }

  func makeEchoProvider() -> Echo_EchoProvider { return EchoProvider() }

  func makeErrorDelegate() -> ServerErrorDelegate? { return nil }

  func makeEchoClient(port: Int) throws -> Echo_EchoClient {
    return Echo_EchoClient(
      channel: try self.makeClientConnection(port: port),
      defaultCallOptions: self.callOptionsWithLogger
    )
  }

  override func setUp() {
    super.setUp()
    self.serverEventLoopGroup = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference
    )
    self.server = try! self.makeServer()

    self.port = self.server.channel.localAddress!.port!

    self.clientEventLoopGroup = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: self.networkPreference
    )
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
  func makeExpectation(
    description: String,
    expectedFulfillmentCount: Int = 1,
    assertForOverFulfill: Bool = true
  ) -> XCTestExpectation {
    let expectation = self.expectation(description: description)
    expectation.expectedFulfillmentCount = expectedFulfillmentCount
    expectation.assertForOverFulfill = assertForOverFulfill
    return expectation
  }

  func makeStatusExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return self.makeExpectation(
      description: "Expecting status received",
      expectedFulfillmentCount: expectedFulfillmentCount
    )
  }

  func makeResponseExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return self.makeExpectation(
      description: "Expecting \(expectedFulfillmentCount) response(s)",
      expectedFulfillmentCount: expectedFulfillmentCount
    )
  }

  func makeRequestExpectation(expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
    return self.makeExpectation(
      description: "Expecting \(expectedFulfillmentCount) request(s) to have been sent",
      expectedFulfillmentCount: expectedFulfillmentCount
    )
  }

  func makeInitialMetadataExpectation() -> XCTestExpectation {
    return self.makeExpectation(description: "Expecting initial metadata")
  }
}
