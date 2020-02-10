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
import GRPC
import EchoImplementation
import EchoModel
import NIO
import NIOHPACK
import XCTest

class MessageCompressionTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var client: ClientConnection!
  var defaultTimeout: TimeInterval = 0.1

  var echo: Echo_EchoServiceClient!

  override func setUp() {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
  }

  func setupServer(encoding: Server.Configuration.MessageEncoding) throws {
    let configuration = Server.Configuration(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.group,
      serviceProviders: [EchoProvider()],
      messageEncoding: encoding
    )

    self.server = try Server.start(configuration: configuration).wait()
  }

  func setupClient(encoding: CallOptions.MessageEncoding) {
    let configuration = ClientConnection.Configuration(
      target: .hostAndPort("localhost", self.server.channel.localAddress!.port!),
      eventLoopGroup: self.group
    )

    self.client = ClientConnection(configuration: configuration)
    self.echo = Echo_EchoServiceClient(
      connection: self.client,
      defaultCallOptions: CallOptions(messageEncoding: encoding)
    )
  }

  func doUnaryRPC() -> UnaryCall<Echo_EchoRequest, Echo_EchoResponse> {
    let get = self.echo.get(.with { $0.text = "foo" })
    return get
  }

  func testCompressedRequestsUncompressedResponses() throws {
    try self.setupServer(encoding: .none)
    self.setupClient(encoding: .init(forRequests: .gzip, acceptableForResponses: [.deflate, .gzip]))

    let get = self.echo.get(.with { $0.text = "foo" })

    let initialMetadata = self.expectation(description: "received initial metadata")
    get.initialMetadata.map {
      $0.contains(name: "grpc-encoding")
    }.assertEqual(false, fulfill: initialMetadata)

    let status = self.expectation(description: "received status")
    get.status.map {
      $0.code
    }.assertEqual(.ok, fulfill: status)

    self.wait(for: [initialMetadata, status], timeout: self.defaultTimeout)
  }

  func testUncompressedRequestsCompressedResponses() throws {
    try self.setupServer(encoding: .enabled)
    self.setupClient(encoding: .init(forRequests: .none, acceptableForResponses: [.deflate, .gzip]))

    let get = self.echo.get(.with { $0.text = "foo" })

    let initialMetadata = self.expectation(description: "received initial metadata")
    get.initialMetadata.map {
      $0.first(name: "grpc-encoding")
    }.assertEqual("deflate", fulfill: initialMetadata)

    let status = self.expectation(description: "received status")
    get.status.map {
      $0.code
    }.assertEqual(.ok, fulfill: status)

    self.wait(for: [initialMetadata, status], timeout: self.defaultTimeout)
  }

  func testServerCanDecompressNonAdvertisedButSupportedCompression() throws {
    // Server should be able to decompress a format it supports but does not advertise. In doing
    // so it must also return a "grpc-accept-encoding" header which includes the value it did not
    // advertise.
    try self.setupServer(encoding: .init(enabled: [.gzip]))
    self.setupClient(encoding: .init(forRequests: .deflate, acceptableForResponses: []))

    let get = self.echo.get(.with { $0.text = "foo" })

    let initialMetadata = self.expectation(description: "received initial metadata")
    get.initialMetadata.map {
      $0[canonicalForm: "grpc-accept-encoding"]
    }.assertEqual(["gzip", "deflate"], fulfill: initialMetadata)

    let status = self.expectation(description: "received status")
    get.status.map {
      $0.code
    }.assertEqual(.ok, fulfill: status)

    self.wait(for: [initialMetadata, status], timeout: self.defaultTimeout)
  }

  func testServerCompressesResponseWithDifferentAlgorithmToRequest() throws {
    // Server should be able to compress responses with a different method to the client, providing
    // the client supports it.
    try self.setupServer(encoding: .init(enabled: [.gzip]))
    self.setupClient(encoding: .init(forRequests: .deflate, acceptableForResponses: [.deflate, .gzip]))

    let get = self.echo.get(.with { $0.text = "foo" })

    let initialMetadata = self.expectation(description: "received initial metadata")
    get.initialMetadata.map {
      $0.first(name: "grpc-encoding")
    }.assertEqual("gzip", fulfill: initialMetadata)

    let status = self.expectation(description: "received status")
    get.status.map {
      $0.code
    }.assertEqual(.ok, fulfill: status)

    self.wait(for: [initialMetadata, status], timeout: self.defaultTimeout)
  }

  func testCompressedRequestWithCompressionNotSupportedOnServer() throws {
    try self.setupServer(encoding: .init(enabled: [.gzip, .deflate]))
    // We can't specify a compression we don't support, so we'll specify no compression and then
    // send a 'grpc-encoding' with our initial metadata.
    self.setupClient(encoding: .init(forRequests: .none, acceptableForResponses: [.deflate, .gzip]))

    let headers: HPACKHeaders = ["grpc-encoding": "you-don't-support-this"]
    let get = self.echo.get(.with { $0.text = "foo" }, callOptions: CallOptions(customMetadata: headers))

    let response = self.expectation(description: "received response")
    get.response.assertError(fulfill: response)

    let trailers = self.expectation(description: "received trailing metadata")
    get.trailingMetadata.map {
      $0[canonicalForm: "grpc-accept-encoding"]
    }.assertEqual(["gzip", "deflate"], fulfill: trailers)

    let status = self.expectation(description: "received status")
    get.status.map {
      $0.code
    }.assertEqual(.unimplemented, fulfill: status)

    self.wait(for: [response, trailers, status], timeout: self.defaultTimeout)
  }
}
