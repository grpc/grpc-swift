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
import NIO
import XCTest

class ClientConnectionBackoffTests: XCTestCase {
  let port = 8080

  var client: EventLoopFuture<ClientConnection>!
  var server: EventLoopFuture<Server>!

  var group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

  override func tearDown() {
    if let server = self.server {
      XCTAssertNoThrow(try server.flatMap { $0.channel.close() }.wait())
    }

    // We don't always expect a client (since we deliberately timeout the connection in some cases).
    if let client = try? self.client.wait() {
      XCTAssertNoThrow(try client.channel.close().wait())
    }

    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
  }

  func makeServer() throws -> EventLoopFuture<Server> {
    return try Server.start(
      hostname: "localhost",
      port: self.port,
      eventLoopGroup: self.group,
      serviceProviders: [])
  }

  func makeClientConfiguration() -> ClientConnection.Configuration {
    return .init(
      target: .hostAndPort("localhost", self.port),
      eventLoopGroup: self.group,
      connectionBackoff: ConnectionBackoff())
  }

  func makeClientConnection(
    _ configuration: ClientConnection.Configuration
  ) -> EventLoopFuture<ClientConnection> {
    return ClientConnection.start(configuration)
  }

  func testClientConnectionFailsWithNoBackoff() throws {
    var configuration = self.makeClientConfiguration()
    configuration.connectionBackoff = nil

    self.client = self.makeClientConnection(configuration)
    XCTAssertThrowsError(try self.client.wait()) { error in
      XCTAssert(error is NIOConnectionError)
    }
  }

  func testClientEventuallyConnects() throws {
    let clientConnected = self.expectation(description: "client connected")
    let serverStarted = self.expectation(description: "server started")

    // Start the client first.
    self.client = self.makeClientConnection(self.makeClientConfiguration())
    self.client.assertSuccess(fulfill: clientConnected)

    // Sleep for a little bit to make sure we hit the backoff.
    Thread.sleep(forTimeInterval: 0.2)

    self.server = try self.makeServer()
    self.server.assertSuccess(fulfill: serverStarted)

    self.wait(for: [serverStarted, clientConnected], timeout: 2.0, enforceOrder: true)
  }

  func testClientEventuallyTimesOut() throws {
    var configuration = self.makeClientConfiguration()
    configuration.connectionBackoff = ConnectionBackoff(maximumBackoff: 0.1)

    self.client = self.makeClientConnection(configuration)
    XCTAssertThrowsError(try self.client.wait()) { error in
      XCTAssert(error is NIOConnectionError)
    }
  }
}
