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
import EchoModel
import GRPC
import NIOCore
import NIOPosix
import XCTest

internal final class RequestIDTests: GRPCTestCase {
  private var server: Server!
  private var group: EventLoopGroup!

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! Server.insecure(group: self.group)
      .withServiceProviders([MetadataEchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func testRequestIDIsPopulatedClientConnection() throws {
    let channel = ClientConnection.insecure(group: self.group)
      .connect(host: "127.0.0.1", port: self.server.channel.localAddress!.port!)

    defer {
      let loop = group.next()
      let promise = loop.makePromise(of: Void.self)
      channel.closeGracefully(deadline: .now() + .seconds(30), promise: promise)
      XCTAssertNoThrow(try promise.futureResult.wait())
    }

    try self._testRequestIDIsPopulated(channel: channel)
  }

  func testRequestIDIsPopulatedChannelPool() throws {
    let channel = try! GRPCChannelPool.with(
      target: .host("127.0.0.1", port: self.server.channel.localAddress!.port!),
      transportSecurity: .plaintext,
      eventLoopGroup: self.group
    )

    defer {
      let loop = group.next()
      let promise = loop.makePromise(of: Void.self)
      channel.closeGracefully(deadline: .now() + .seconds(30), promise: promise)
      XCTAssertNoThrow(try promise.futureResult.wait())
    }

    try self._testRequestIDIsPopulated(channel: channel)
  }

  func _testRequestIDIsPopulated(channel: GRPCChannel) throws {
    let echo = Echo_EchoNIOClient(channel: channel)
    let options = CallOptions(
      requestIDProvider: .userDefined("foo"),
      requestIDHeader: "request-id-header"
    )

    let get = echo.get(.with { $0.text = "ignored" }, callOptions: options)
    let response = try get.response.wait()
    XCTAssert(response.text.contains("request-id-header: foo"))
  }
}
