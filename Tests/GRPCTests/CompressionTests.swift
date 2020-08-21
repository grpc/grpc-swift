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
import EchoImplementation
import EchoModel
import GRPC
import NIO
import NIOHPACK
import XCTest

class MessageCompressionTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var client: ClientConnection!
  var defaultTimeout: TimeInterval = 1.0

  var echo: Echo_EchoClient!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func setupServer(encoding: ServerMessageEncoding) throws {
    self.server = try Server.insecure(group: self.group)
      .withServiceProviders([EchoProvider()])
      .withMessageCompression(encoding)
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()
  }

  func setupClient(encoding: ClientMessageEncoding) {
    self.client = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server.channel.localAddress!.port!)

    self.echo = Echo_EchoClient(
      channel: self.client,
      defaultCallOptions: CallOptions(messageEncoding: encoding, logger: self.clientLogger)
    )
  }

  func testCompressedRequestsUncompressedResponses() throws {
    // Enable compression, but don't advertise that it's enabled.
    // The spec says that servers should handle compression they support but don't advertise.
    try self
      .setupServer(encoding: .enabled(.init(enabledAlgorithms: [], decompressionLimit: .ratio(10))))
    self.setupClient(encoding: .enabled(.init(
      forRequests: .gzip,
      acceptableForResponses: [.deflate, .gzip],
      decompressionLimit: .ratio(10)
    )))

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
    try self.setupServer(encoding: .enabled(.init(decompressionLimit: .ratio(10))))
    self.setupClient(encoding: .enabled(.init(
      forRequests: .none,
      acceptableForResponses: [.deflate, .gzip],
      decompressionLimit: .ratio(10)
    )))

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
    try self
      .setupServer(encoding: .enabled(.init(
        enabledAlgorithms: [.gzip],
        decompressionLimit: .ratio(10)
      )))
    self
      .setupClient(encoding: .enabled(.init(
        forRequests: .deflate,
        acceptableForResponses: [],
        decompressionLimit: .ratio(10)
      )))

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
    try self
      .setupServer(encoding: .enabled(.init(
        enabledAlgorithms: [.gzip],
        decompressionLimit: .ratio(10)
      )))
    self.setupClient(encoding: .enabled(.init(
      forRequests: .deflate,
      acceptableForResponses: [.deflate, .gzip],
      decompressionLimit: .ratio(10)
    )))

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
    try self
      .setupServer(encoding: .enabled(.init(
        enabledAlgorithms: [.gzip, .deflate],
        decompressionLimit: .ratio(10)
      )))
    // We can't specify a compression we don't support, so we'll specify no compression and then
    // send a 'grpc-encoding' with our initial metadata.
    self.setupClient(encoding: .enabled(.init(
      forRequests: .none,
      acceptableForResponses: [.deflate, .gzip],
      decompressionLimit: .ratio(10)
    )))

    let headers: HPACKHeaders = ["grpc-encoding": "you-don't-support-this"]
    let get = self.echo.get(
      .with { $0.text = "foo" },
      callOptions: CallOptions(customMetadata: headers)
    )

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

  func testDecompressionLimitIsRespectedByServerForUnaryCall() throws {
    try self.setupServer(encoding: .enabled(.init(decompressionLimit: .absolute(1))))
    self
      .setupClient(encoding: .enabled(.init(
        forRequests: .gzip,
        decompressionLimit: .absolute(1024)
      )))

    let get = self.echo.get(.with { $0.text = "foo" })
    let status = self.expectation(description: "received status")

    get.status.map {
      $0.code
    }.assertEqual(.resourceExhausted, fulfill: status)

    self.wait(for: [status], timeout: self.defaultTimeout)
  }

  func testDecompressionLimitIsRespectedByServerForStreamingCall() throws {
    try self.setupServer(encoding: .enabled(.init(decompressionLimit: .absolute(1024))))
    self
      .setupClient(encoding: .enabled(.init(
        forRequests: .gzip,
        decompressionLimit: .absolute(2048)
      )))

    let collect = self.echo.collect()
    let status = self.expectation(description: "received status")

    // Smaller than limit.
    collect.sendMessage(.with { $0.text = "foo" }, promise: nil)
    // Should be just over the limit.
    collect.sendMessage(.with { $0.text = String(repeating: "x", count: 1024) }, promise: nil)
    collect.sendEnd(promise: nil)

    collect.status.map {
      $0.code
    }.assertEqual(.resourceExhausted, fulfill: status)

    self.wait(for: [status], timeout: self.defaultTimeout)
  }

  func testDecompressionLimitIsRespectedByClientForUnaryCall() throws {
    try self
      .setupServer(encoding: .enabled(.init(
        enabledAlgorithms: [.gzip],
        decompressionLimit: .absolute(1024)
      )))
    self.setupClient(encoding: .enabled(.responsesOnly(decompressionLimit: .absolute(1))))

    let get = self.echo.get(.with { $0.text = "foo" })
    let status = self.expectation(description: "received status")

    get.status.map {
      $0.code
    }.assertEqual(.resourceExhausted, fulfill: status)

    self.wait(for: [status], timeout: self.defaultTimeout)
  }

  func testDecompressionLimitIsRespectedByClientForStreamingCall() throws {
    try self.setupServer(encoding: .enabled(.init(decompressionLimit: .absolute(2048))))
    self
      .setupClient(encoding: .enabled(.init(
        forRequests: .gzip,
        decompressionLimit: .absolute(1024)
      )))

    var responses: [Echo_EchoResponse] = []
    let update = self.echo.update {
      responses.append($0)
    }

    let status = self.expectation(description: "received status")

    // Smaller than limit.
    update.sendMessage(.with { $0.text = "foo" }, promise: nil)
    // Should be just over the limit.
    update.sendMessage(.with { $0.text = String(repeating: "x", count: 1024) }, promise: nil)
    update.sendEnd(promise: nil)

    update.status.map {
      $0.code
    }.assertEqual(.resourceExhausted, fulfill: status)

    self.wait(for: [status], timeout: self.defaultTimeout)
    XCTAssertEqual(responses.count, 1)
  }
}
