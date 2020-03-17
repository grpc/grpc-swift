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
import EchoModel
import EchoImplementation
import NIO
import NIOSSL
import XCTest

class ClientTLSHostnameOverrideTests: GRPCTestCase {
  var eventLoopGroup: EventLoopGroup!
  var server: Server!
  var connection: ClientConnection!

  override func setUp() {
    super.setUp()
    self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    super.tearDown()
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try connection.close().wait())
    XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
  }


  func doTestUnary() throws {
    let client = Echo_EchoClient(channel: self.connection)
    let get = client.get(.with { $0.text = "foo" })

    let response = try get.response.wait()
    XCTAssertEqual(response.text, "Swift echo get: foo")

    let status = try get.status.wait()
    XCTAssertEqual(status.code, .ok)
  }

  func testTLSWithHostnameOverride() throws {
    // Run a server presenting a certificate for example.com on localhost.
    let cert = SampleCertificate.exampleServer.certificate
    let key = SamplePrivateKey.exampleServer

    self.server = try Server.secure(group: self.eventLoopGroup, certificateChain: [cert], privateKey: key)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withServiceProviders([EchoProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.secure(group: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withTLS(serverHostnameOverride: "example.com")
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }

  func testTLSWithoutHostnameOverride() throws {
    // Run a server presenting a certificate for localhost on localhost.
    let cert = SampleCertificate.server.certificate
    let key = SamplePrivateKey.server

    self.server = try Server.secure(group: self.eventLoopGroup, certificateChain: [cert], privateKey: key)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withServiceProviders([EchoProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.secure(group: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }
}
