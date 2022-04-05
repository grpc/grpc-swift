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
#if canImport(NIOSSL)
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCSampleData
import NIOCore
import NIOPosix
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
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.connection.close().wait())
    XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
    super.tearDown()
  }

  func doTestUnary() throws {
    let client = Echo_EchoNIOClient(
      channel: self.connection,
      defaultCallOptions: self.callOptionsWithLogger
    )
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

    self.server = try Server.usingTLSBackedByNIOSSL(
      on: self.eventLoopGroup,
      certificateChain: [cert],
      privateKey: key
    )
    .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
    .withServiceProviders([EchoProvider()])
    .withLogger(self.serverLogger)
    .bind(host: "localhost", port: 0)
    .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.usingTLSBackedByNIOSSL(on: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withTLS(serverHostnameOverride: "example.com")
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }

  func testTLSWithoutHostnameOverride() throws {
    // Run a server presenting a certificate for localhost on localhost.
    let cert = SampleCertificate.server.certificate
    let key = SamplePrivateKey.server

    self.server = try Server.usingTLSBackedByNIOSSL(
      on: self.eventLoopGroup,
      certificateChain: [cert],
      privateKey: key
    )
    .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
    .withServiceProviders([EchoProvider()])
    .withLogger(self.serverLogger)
    .bind(host: "localhost", port: 0)
    .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.usingTLSBackedByNIOSSL(on: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }

  func testTLSWithNoCertificateVerification() throws {
    self.server = try Server.usingTLSBackedByNIOSSL(
      on: self.eventLoopGroup,
      certificateChain: [SampleCertificate.server.certificate],
      privateKey: SamplePrivateKey.server
    )
    .withServiceProviders([EchoProvider()])
    .withLogger(self.serverLogger)
    .bind(host: "localhost", port: 0)
    .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.usingTLSBackedByNIOSSL(on: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([]))
      .withTLS(certificateVerification: .none)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }

  func testAuthorityUsesTLSHostnameOverride() throws {
    // This test validates that when suppled with a server hostname override, the client uses it
    // as the ":authority" pseudo-header.

    self.server = try Server.usingTLSBackedByNIOSSL(
      on: self.eventLoopGroup,
      certificateChain: [SampleCertificate.exampleServer.certificate],
      privateKey: SamplePrivateKey.exampleServer
    )
    .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
    .withServiceProviders([AuthorityCheckingEcho()])
    .withLogger(self.serverLogger)
    .bind(host: "localhost", port: 0)
    .wait()

    guard let port = self.server.channel.localAddress?.port else {
      XCTFail("could not get server port")
      return
    }

    self.connection = ClientConnection.usingTLSBackedByNIOSSL(on: self.eventLoopGroup)
      .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
      .withTLS(serverHostnameOverride: "example.com")
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: port)

    try self.doTestUnary()
  }
}

private class AuthorityCheckingEcho: Echo_EchoProvider {
  var interceptors: Echo_EchoServerInterceptorFactoryProtocol?

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    guard let authority = context.headers.first(name: ":authority") else {
      let status = GRPCStatus(
        code: .failedPrecondition,
        message: "Missing ':authority' pseudo header"
      )
      return context.eventLoop.makeFailedFuture(status)
    }

    XCTAssertEqual(authority, SampleCertificate.exampleServer.commonName)
    XCTAssertNotEqual(authority, "localhost")

    return context.eventLoop.makeSucceededFuture(.with {
      $0.text = "Swift echo get: \(request.text)"
    })
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    preconditionFailure("Not implemented")
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    preconditionFailure("Not implemented")
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    preconditionFailure("Not implemented")
  }
}

#endif // canImport(NIOSSL)
