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

final class ClientEventLoopPreferenceTests: GRPCTestCase {
  private var group: MultiThreadedEventLoopGroup!

  private var serverLoop: EventLoop!
  private var clientLoop: EventLoop!
  private var clientCallbackLoop: EventLoop!

  private var server: Server!
  private var connection: ClientConnection!

  private var echo: Echo_EchoClient {
    let options = CallOptions(
      eventLoopPreference: .exact(self.clientCallbackLoop),
      logger: self.clientLogger
    )

    return Echo_EchoClient(channel: self.connection, defaultCallOptions: options)
  }

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 3)
    self.serverLoop = self.group.next()
    self.clientLoop = self.group.next()
    self.clientCallbackLoop = self.group.next()

    XCTAssert(self.serverLoop !== self.clientLoop)
    XCTAssert(self.serverLoop !== self.clientCallbackLoop)
    XCTAssert(self.clientLoop !== self.clientCallbackLoop)

    self.server = try! Server.insecure(group: self.serverLoop)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    self.connection = ClientConnection.insecure(group: self.clientLoop)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server.channel.localAddress!.port!)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.connection.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())

    super.tearDown()
  }

  private func assertClientCallbackEventLoop(_ eventLoop: EventLoop, line: UInt = #line) {
    XCTAssert(eventLoop === self.clientCallbackLoop, line: line)
  }

  func testUnaryWithDifferentEventLoop() throws {
    let get = self.echo.get(.with { $0.text = "Hello!" })

    self.assertClientCallbackEventLoop(get.eventLoop)
    self.assertClientCallbackEventLoop(get.initialMetadata.eventLoop)
    self.assertClientCallbackEventLoop(get.response.eventLoop)
    self.assertClientCallbackEventLoop(get.trailingMetadata.eventLoop)
    self.assertClientCallbackEventLoop(get.status.eventLoop)

    assertThat(try get.response.wait(), .is(.with { $0.text = "Swift echo get: Hello!" }))
    assertThat(try get.status.wait(), .hasCode(.ok))
  }

  func testClientStreamingWithDifferentEventLoop() throws {
    let collect = self.echo.collect()

    self.assertClientCallbackEventLoop(collect.eventLoop)
    self.assertClientCallbackEventLoop(collect.initialMetadata.eventLoop)
    self.assertClientCallbackEventLoop(collect.response.eventLoop)
    self.assertClientCallbackEventLoop(collect.trailingMetadata.eventLoop)
    self.assertClientCallbackEventLoop(collect.status.eventLoop)

    XCTAssertNoThrow(try collect.sendMessage(.with { $0.text = "a" }).wait())
    XCTAssertNoThrow(try collect.sendEnd().wait())

    assertThat(try collect.response.wait(), .is(.with { $0.text = "Swift echo collect: a" }))
    assertThat(try collect.status.wait(), .hasCode(.ok))
  }

  func testServerStreamingWithDifferentEventLoop() throws {
    let response = self.clientCallbackLoop.makePromise(of: Void.self)

    let expand = self.echo.expand(.with { $0.text = "a" }) { _ in
      self.clientCallbackLoop.preconditionInEventLoop()
      response.succeed(())
    }

    self.assertClientCallbackEventLoop(expand.eventLoop)
    self.assertClientCallbackEventLoop(expand.initialMetadata.eventLoop)
    self.assertClientCallbackEventLoop(expand.trailingMetadata.eventLoop)
    self.assertClientCallbackEventLoop(expand.status.eventLoop)

    XCTAssertNoThrow(try response.futureResult.wait())
    assertThat(try expand.status.wait(), .hasCode(.ok))
  }

  func testBidirectionalStreamingWithDifferentEventLoop() throws {
    let response = self.clientCallbackLoop.makePromise(of: Void.self)

    let update = self.echo.update { _ in
      self.clientCallbackLoop.preconditionInEventLoop()
      response.succeed(())
    }

    self.assertClientCallbackEventLoop(update.eventLoop)
    self.assertClientCallbackEventLoop(update.initialMetadata.eventLoop)
    self.assertClientCallbackEventLoop(update.trailingMetadata.eventLoop)
    self.assertClientCallbackEventLoop(update.status.eventLoop)

    XCTAssertNoThrow(try update.sendMessage(.with { $0.text = "a" }).wait())
    XCTAssertNoThrow(try update.sendEnd().wait())

    XCTAssertNoThrow(try response.futureResult.wait())
    assertThat(try update.status.wait(), .hasCode(.ok))
  }
}
