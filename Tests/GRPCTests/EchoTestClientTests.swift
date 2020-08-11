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
import XCTest

/// An example model using a generated client for the 'Echo' service.
///
/// This demonstrates how one might extract a generated client into a component which could be
/// backed by a real or fake client.
class EchoModel {
  private let client: Echo_EchoClientProtocol

  init(client: Echo_EchoClientProtocol) {
    self.client = client
  }

  /// Call 'get' with the given word and call the `callback` with the result.
  func getWord(_ text: String, _ callback: @escaping (Result<String, Error>) -> Void) {
    let get = self.client.get(.with { $0.text = text })
    get.response.whenComplete { result in
      switch result {
      case let .success(response):
        callback(.success(response.text))
      case let .failure(error):
        callback(.failure(error))
      }
    }
  }

  /// Call 'update' with the given words. Call `onResponse` for each response and then `onEnd` when
  /// the RPC has completed.
  func updateWords(
    _ words: [String],
    onResponse: @escaping (String) -> Void,
    onEnd: @escaping (GRPCStatus) -> Void
  ) {
    let update = self.client.update { response in
      onResponse(response.text)
    }

    update.status.whenSuccess { status in
      onEnd(status)
    }

    update.sendMessages(words.map { word in .with { $0.text = word } }, promise: nil)
    update.sendEnd(promise: nil)
  }
}

class EchoTestClientTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup?
  private var server: Server?
  private var channel: ClientConnection?

  private func setUpServerAndChannel() throws -> ClientConnection {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.group = group

    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    self.server = server

    let channel = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: server.channel.localAddress!.port!)

    self.channel = channel

    return channel
  }

  override func tearDown() {
    if let channel = self.channel {
      XCTAssertNoThrow(try channel.close().wait())
    }
    if let server = self.server {
      XCTAssertNoThrow(try server.close().wait())
    }
    if let group = self.group {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    super.tearDown()
  }

  func testGetWithTestClient() {
    let client = Echo_EchoTestClient(defaultCallOptions: self.callOptionsWithLogger)
    let model = EchoModel(client: client)

    let completed = self.expectation(description: "'Get' completed")

    // Enqueue a response for the next call to Get.
    client.enqueueGetResponse(.with { $0.text = "Expected response" })

    model.getWord("Hello") { result in
      switch result {
      case let .success(text):
        XCTAssertEqual(text, "Expected response")
      case let .failure(error):
        XCTFail("Unexpected error \(error)")
      }

      completed.fulfill()
    }

    self.wait(for: [completed], timeout: 10.0)
  }

  func testGetWithRealClientAndServer() throws {
    let channel = try self.setUpServerAndChannel()
    let client = Echo_EchoClient(channel: channel, defaultCallOptions: self.callOptionsWithLogger)
    let model = EchoModel(client: client)

    let completed = self.expectation(description: "'Get' completed")

    model.getWord("Hello") { result in
      switch result {
      case let .success(text):
        XCTAssertEqual(text, "Swift echo get: Hello")
      case let .failure(error):
        XCTFail("Unexpected error \(error)")
      }

      completed.fulfill()
    }

    self.wait(for: [completed], timeout: 10.0)
  }

  func testUpdateWithTestClient() {
    let client = Echo_EchoTestClient(defaultCallOptions: self.callOptionsWithLogger)
    let model = EchoModel(client: client)

    let completed = self.expectation(description: "'Update' completed")
    let responses = self.expectation(description: "Received responses")
    responses.expectedFulfillmentCount = 3

    // Create a response stream for 'Update'.
    let stream = client.makeUpdateResponseStream()

    model.updateWords(["foo", "bar", "baz"], onResponse: { response in
      XCTAssertEqual(response, "Expected response")
      responses.fulfill()
    }, onEnd: { status in
      XCTAssertEqual(status.code, .ok)
      completed.fulfill()
    })

    // Send some responses:
    XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = "Expected response" }))
    XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = "Expected response" }))
    XCTAssertNoThrow(try stream.sendMessage(.with { $0.text = "Expected response" }))
    XCTAssertNoThrow(try stream.sendEnd())

    self.wait(for: [responses, completed], timeout: 10.0)
  }

  func testUpdateWithRealClientAndServer() throws {
    let channel = try self.setUpServerAndChannel()
    let client = Echo_EchoClient(channel: channel, defaultCallOptions: self.callOptionsWithLogger)
    let model = EchoModel(client: client)

    let completed = self.expectation(description: "'Update' completed")
    let responses = self.expectation(description: "Received responses")
    responses.expectedFulfillmentCount = 3

    model.updateWords(["foo", "bar", "baz"], onResponse: { response in
      XCTAssertTrue(response.hasPrefix("Swift echo update"))
      responses.fulfill()
    }, onEnd: { status in
      XCTAssertEqual(status.code, .ok)
      completed.fulfill()
    })

    self.wait(for: [responses, completed], timeout: 10.0)
  }
}
