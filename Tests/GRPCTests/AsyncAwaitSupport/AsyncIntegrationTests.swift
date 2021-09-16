/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.5)
import EchoImplementation
import EchoModel
import GRPC
import NIOCore
import NIOHPACK
import NIOPosix
import XCTest

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
final class AsyncIntegrationTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var server: Server!
  private var client: GRPCChannel!

  private var echo: Echo_EchoAsyncClient {
    return .init(channel: self.client, defaultCallOptions: self.callOptionsWithLogger)
  }

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    self.server = try! Server.insecure(group: self.group)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoAsyncProvider()])
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    let port = self.server.channel.localAddress!.port!
    self.client = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: port)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func testUnary() {
    XCTAsyncTest {
      let get = self.echo.makeGetCall(.with { $0.text = "hello" })

      let initialMetadata = try await get.initialMetadata
      initialMetadata.assertFirst("200", forName: ":status")

      let response = try await get.response
      XCTAssertEqual(response.text, "Swift echo get: hello")

      let trailingMetadata = try await get.trailingMetadata
      trailingMetadata.assertFirst("0", forName: "grpc-status")

      let status = await get.status
      XCTAssertTrue(status.isOk)
    }
  }

  func testClientStreaming() {
    XCTAsyncTest {
      let collect = self.echo.makeCollectCall()

      try await collect.requestStream.send(.with { $0.text = "boyle" })
      try await collect.requestStream.send(.with { $0.text = "jeffers" })
      try await collect.requestStream.send(.with { $0.text = "holt" })
      try await collect.requestStream.finish()

      let initialMetadata = try await collect.initialMetadata
      initialMetadata.assertFirst("200", forName: ":status")

      let response = try await collect.response
      XCTAssertEqual(response.text, "Swift echo collect: boyle jeffers holt")

      let trailingMetadata = try await collect.trailingMetadata
      trailingMetadata.assertFirst("0", forName: "grpc-status")

      let status = await collect.status
      XCTAssertTrue(status.isOk)
    }
  }

  func testServerStreaming() {
    XCTAsyncTest {
      let expand = self.echo.makeExpandCall(.with { $0.text = "boyle jeffers holt" })

      let initialMetadata = try await expand.initialMetadata
      initialMetadata.assertFirst("200", forName: ":status")

      let respones = try await expand.responses.map { $0.text }.collect()
      XCTAssertEqual(respones, [
        "Swift echo expand (0): boyle",
        "Swift echo expand (1): jeffers",
        "Swift echo expand (2): holt",
      ])

      let trailingMetadata = try await expand.trailingMetadata
      trailingMetadata.assertFirst("0", forName: "grpc-status")

      let status = await expand.status
      XCTAssertTrue(status.isOk)
    }
  }

  func testBidirectionalStreaming() {
    XCTAsyncTest {
      let update = self.echo.makeUpdateCall()

      var responseIterator = update.responses.map { $0.text }.makeAsyncIterator()

      for (i, name) in ["boyle", "jeffers", "holt"].enumerated() {
        try await update.requestStream.send(.with { $0.text = name })
        let response = try await responseIterator.next()
        XCTAssertEqual(response, "Swift echo update (\(i)): \(name)")
      }

      try await update.requestStream.finish()

      // This isn't right after we make the call as servers are not guaranteed to send metadata back
      // immediately. Concretely, we don't send initial metadata back until the first response
      // message is sent by the server.
      let initialMetadata = try await update.initialMetadata
      initialMetadata.assertFirst("200", forName: ":status")

      let trailingMetadata = try await update.trailingMetadata
      trailingMetadata.assertFirst("0", forName: "grpc-status")

      let status = await update.status
      XCTAssertTrue(status.isOk)
    }
  }
}

extension HPACKHeaders {
  func assertFirst(_ value: String, forName name: String) {
    XCTAssertEqual(self.first(name: name), value)
  }
}

#endif // compiler(>=5.5)
