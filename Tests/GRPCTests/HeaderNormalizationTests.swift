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
@testable import GRPC
import EchoModel
import EchoImplementation
import NIO
import NIOHTTP1
import NIOHPACK
import XCTest

class EchoMetadataValidator: Echo_EchoProvider {
  private func assertCustomMetadataIsLowercased(
    _ headers: HTTPHeaders,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    // Header lookup is case-insensitive so we need to pull out the values we know the client sent
    // as custom-metadata and then compare a new set of headers.
    let customMetadata = HTTPHeaders(headers.filter { name, value in value == "client" })
    XCTAssertEqual(customMetadata, ["client": "client"], file: file, line: line)
  }

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    self.assertCustomMetadataIsLowercased(context.request.headers)
    context.trailingMetadata.add(name: "SERVER", value: "server")
    return context.eventLoop.makeSucceededFuture(.with { $0.text = request.text })
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    self.assertCustomMetadataIsLowercased(context.request.headers)
    context.trailingMetadata.add(name: "SERVER", value: "server")
    return context.eventLoop.makeSucceededFuture(.ok)
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    self.assertCustomMetadataIsLowercased(context.request.headers)
    context.trailingMetadata.add(name: "SERVER", value: "server")
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message:
        ()
      case .end:
        context.responsePromise.succeed(.with { $0.text = "foo" })
      }
    })
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    self.assertCustomMetadataIsLowercased(context.request.headers)
    context.trailingMetadata.add(name: "SERVER", value: "server")
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message:
        ()
      case .end:
        context.statusPromise.succeed(.ok)
      }
    })
  }
}

class HeaderNormalizationTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var channel: GRPCChannel!
  var client: Echo_EchoClient!

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let serverConfig = Server.Configuration(
      target: .hostAndPort("localhost", 0),
      eventLoopGroup: self.group,
      serviceProviders: [EchoMetadataValidator()]
    )

    self.server = try! Server.start(configuration: serverConfig).wait()

    let clientConfig = ClientConnection.Configuration(
      target: .hostAndPort("localhost", self.server.channel.localAddress!.port!),
      eventLoopGroup: self.group
    )

    self.channel = ClientConnection(configuration: clientConfig)
    self.client = Echo_EchoClient(channel: self.channel)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
  }

  private func assertCustomMetadataIsLowercased(
    _ headers: EventLoopFuture<HPACKHeaders>,
    expectation: XCTestExpectation,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    // Header lookup is case-insensitive so we need to pull out the values we know the server sent
    // us as trailing-metadata and then compare a new set of headers.
    headers.map { trailers -> HPACKHeaders in
      let filtered = trailers.filter {
        $0.value == "server"
      }.map { (name, value, indexing) in
        return (name, value)
      }
      return HPACKHeaders(filtered)
    }.assertEqual(["server": "server"], fulfill: expectation, file: file, line: line)
  }

  func testHeadersAreNormalizedForUnary() throws {
    let trailingMetadata = self.expectation(description: "received trailing metadata")
    let options = CallOptions(customMetadata: ["CLIENT": "client"])
    let rpc = self.client.get(.with { $0.text = "foo" }, callOptions: options)
    self.assertCustomMetadataIsLowercased(rpc.trailingMetadata, expectation: trailingMetadata)
    self.wait(for: [trailingMetadata], timeout: 1.0)
  }

  func testHeadersAreNormalizedForClientStreaming() throws {
    let trailingMetadata = self.expectation(description: "received trailing metadata")
    let options = CallOptions(customMetadata: ["CLIENT": "client"])
    let rpc = self.client.collect(callOptions: options)
    rpc.sendEnd(promise: nil)
    self.assertCustomMetadataIsLowercased(rpc.trailingMetadata, expectation: trailingMetadata)
    self.wait(for: [trailingMetadata], timeout: 1.0)
  }

  func testHeadersAreNormalizedForServerStreaming() throws {
    let trailingMetadata = self.expectation(description: "received trailing metadata")
    let options = CallOptions(customMetadata: ["CLIENT": "client"])
    let rpc = self.client.expand(.with { $0.text = "foo" }, callOptions: options) {
      XCTFail("unexpected response: \($0)")
    }
    self.assertCustomMetadataIsLowercased(rpc.trailingMetadata, expectation: trailingMetadata)
    self.wait(for: [trailingMetadata], timeout: 1.0)
  }

  func testHeadersAreNormalizedForBidirectionalStreaming() throws {
    let trailingMetadata = self.expectation(description: "received trailing metadata")
    let options = CallOptions(customMetadata: ["CLIENT": "client"])
    let rpc = self.client.update(callOptions: options) {
      XCTFail("unexpected response: \($0)")
    }
    rpc.sendEnd(promise: nil)
    self.assertCustomMetadataIsLowercased(rpc.trailingMetadata, expectation: trailingMetadata)
    self.wait(for: [trailingMetadata], timeout: 1.0)
  }
}
