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
import EchoImplementation
import EchoModel
import GRPC
import NIOCore
import NIOPosix
import XCTest

final class GRPCMessageLengthLimitTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var server: Server!
  private var connection: ClientConnection!

  private var echo: Echo_EchoClient {
    return Echo_EchoClient(channel: self.connection)
  }

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.connection?.close().wait())
    XCTAssertNoThrow(try self.server?.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  private func startEchoServer(receiveLimit: Int) throws {
    self.server = try Server.insecure(group: self.group)
      .withServiceProviders([EchoProvider()])
      .withMaximumReceiveMessageLength(receiveLimit)
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  private func startConnection(receiveLimit: Int) {
    self.connection = ClientConnection.insecure(group: self.group)
      .withMaximumReceiveMessageLength(receiveLimit)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "127.0.0.1", port: self.server.channel.localAddress!.port!)
  }

  private func makeRequest(minimumLength: Int) -> Echo_EchoRequest {
    return .with {
      $0.text = String(repeating: "x", count: minimumLength)
    }
  }

  func testServerRejectsLongUnaryRequest() throws {
    // Server limits request size to 1024, no client limits.
    try self.startEchoServer(receiveLimit: 1024)
    self.startConnection(receiveLimit: .max)

    let get = self.echo.get(self.makeRequest(minimumLength: 1024))
    XCTAssertThrowsError(try get.response.wait())
    XCTAssertEqual(try get.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testServerRejectsLongClientStreamingRequest() throws {
    try self.startEchoServer(receiveLimit: 1024)
    self.startConnection(receiveLimit: .max)

    let collect = self.echo.collect()
    XCTAssertNoThrow(try collect.sendMessage(self.makeRequest(minimumLength: 1)).wait())
    XCTAssertNoThrow(try collect.sendMessage(self.makeRequest(minimumLength: 1024)).wait())
    // (No need to send end, the server is going to close the RPC because the message was too long.)

    XCTAssertThrowsError(try collect.response.wait())
    XCTAssertEqual(try collect.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testServerRejectsLongServerStreamingRequest() throws {
    try self.startEchoServer(receiveLimit: 1024)
    self.startConnection(receiveLimit: .max)

    let expand = self.echo.expand(self.makeRequest(minimumLength: 1024)) { _ in
      XCTFail("Unexpected response")
    }

    XCTAssertEqual(try expand.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testServerRejectsLongBidirectionalStreamingRequest() throws {
    try self.startEchoServer(receiveLimit: 1024)
    self.startConnection(receiveLimit: .max)

    let update = self.echo.update { _ in }

    XCTAssertNoThrow(try update.sendMessage(self.makeRequest(minimumLength: 1)).wait())
    XCTAssertNoThrow(try update.sendMessage(self.makeRequest(minimumLength: 1024)).wait())
    // (No need to send end, the server is going to close the RPC because the message was too long.)

    XCTAssertEqual(try update.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testClientRejectsLongUnaryResponse() throws {
    // No server limits, client limits response size to 1024.
    try self.startEchoServer(receiveLimit: .max)
    self.startConnection(receiveLimit: 1024)

    let get = self.echo.get(.with { $0.text = String(repeating: "x", count: 1024) })
    XCTAssertThrowsError(try get.response.wait())
    XCTAssertEqual(try get.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testClientRejectsLongClientStreamingResponse() throws {
    try self.startEchoServer(receiveLimit: .max)
    self.startConnection(receiveLimit: 1024)

    let collect = self.echo.collect()
    XCTAssertNoThrow(try collect.sendMessage(self.makeRequest(minimumLength: 1)).wait())
    XCTAssertNoThrow(try collect.sendMessage(self.makeRequest(minimumLength: 1024)).wait())
    XCTAssertNoThrow(try collect.sendEnd().wait())

    XCTAssertThrowsError(try collect.response.wait())
    XCTAssertEqual(try collect.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testClientRejectsLongServerStreamingRequest() throws {
    try self.startEchoServer(receiveLimit: .max)
    self.startConnection(receiveLimit: 1024)

    let expand = self.echo.expand(self.makeRequest(minimumLength: 1024)) { _ in
      // Expand splits on spaces, there are no spaces in the request and it should be too long for
      // the client to expect it.
      XCTFail("Unexpected response")
    }

    XCTAssertEqual(try expand.status.map { $0.code }.wait(), .resourceExhausted)
  }

  func testClientRejectsLongServerBidirectionalStreamingResponse() throws {
    try self.startEchoServer(receiveLimit: .max)
    self.startConnection(receiveLimit: 1024)

    let update = self.echo.update { _ in }

    XCTAssertNoThrow(try update.sendMessage(self.makeRequest(minimumLength: 1)).wait())
    XCTAssertNoThrow(try update.sendMessage(self.makeRequest(minimumLength: 1024)).wait())
    // (No need to send end, the client will close the RPC when it receives a response which is too
    // long.

    XCTAssertEqual(try update.status.map { $0.code }.wait(), .resourceExhausted)
  }
}
