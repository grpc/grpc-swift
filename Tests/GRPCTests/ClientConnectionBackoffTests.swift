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
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import NIO
import NIOConcurrencyHelpers
import XCTest

class ClientConnectionBackoffTests: GRPCTestCase {
  let port = 8080

  var client: ClientConnection!
  var server: EventLoopFuture<Server>!

  var serverGroup: EventLoopGroup!
  var clientGroup: EventLoopGroup!

  var connectionStateRecorder = RecordingConnectivityDelegate()

  override func setUp() {
    super.setUp()
    self.serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  override func tearDown() {
    // We have additional state changes during tear down, in some cases we can over-fulfill a test
    // expectation which causes false negatives.
    self.client.connectivity.delegate = nil

    if let server = self.server {
      XCTAssertNoThrow(try server.flatMap { $0.channel.close() }.wait())
    }
    XCTAssertNoThrow(try? self.serverGroup.syncShutdownGracefully())
    self.server = nil
    self.serverGroup = nil

    // We don't always expect a client to be closed cleanly, since in some cases we deliberately
    // timeout the connection.
    try? self.client.close().wait()
    XCTAssertNoThrow(try self.clientGroup.syncShutdownGracefully())
    self.client = nil
    self.clientGroup = nil

    super.tearDown()
  }

  func makeServer() -> EventLoopFuture<Server> {
    return Server.insecure(group: self.serverGroup)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: self.port)
  }

  func connectionBuilder() -> ClientConnection.Builder {
    return ClientConnection.insecure(group: self.clientGroup)
      .withConnectivityStateDelegate(self.connectionStateRecorder)
      .withConnectionBackoff(maximum: .milliseconds(100))
      .withConnectionTimeout(minimum: .milliseconds(100))
      .withBackgroundActivityLogger(self.clientLogger)
  }

  func testClientConnectionFailsWithNoBackoff() throws {
    self.connectionStateRecorder.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .shutdown),
      ])
    }

    self.client = self.connectionBuilder()
      .withConnectionReestablishment(enabled: false)
      .connect(host: "localhost", port: self.port)

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: self.client, defaultCallOptions: self.callOptionsWithLogger)
    _ = echo.get(.with { $0.text = "foo" })

    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))
  }

  func testClientConnectionFailureIsLimited() throws {
    self.connectionStateRecorder.expectChanges(4) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .transientFailure),
        Change(from: .transientFailure, to: .connecting),
        Change(from: .connecting, to: .shutdown),
      ])
    }

    self.client = self.connectionBuilder()
      .withConnectionBackoff(retries: .upTo(1))
      .connect(host: "localhost", port: self.port)

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: self.client, defaultCallOptions: self.callOptionsWithLogger)
    _ = echo.get(.with { $0.text = "foo" })

    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))
  }

  func testClientEventuallyConnects() throws {
    self.connectionStateRecorder.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .transientFailure),
      ])
    }

    // Start the client first.
    self.client = self.connectionBuilder()
      .connect(host: "localhost", port: self.port)

    // Start an RPC to trigger creating a channel.
    let echo = Echo_EchoClient(channel: self.client, defaultCallOptions: self.callOptionsWithLogger)
    _ = echo.get(.with { $0.text = "foo" })

    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))

    self.connectionStateRecorder.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .transientFailure, to: .connecting),
        Change(from: .connecting, to: .ready),
      ])
    }

    self.server = self.makeServer()
    let serverStarted = self.expectation(description: "server started")
    self.server.assertSuccess(fulfill: serverStarted)

    self.wait(for: [serverStarted], timeout: 5.0)
    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))
  }

  func testClientReconnectsAutomatically() throws {
    // Wait for the server to start.
    self.server = self.makeServer()
    let server = try self.server.wait()

    // Prepare the delegate so it expects the connection to hit `.ready`.
    self.connectionStateRecorder.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .ready),
      ])
    }

    // Configure the client backoff to have a short backoff.
    self.client = self.connectionBuilder()
      .withConnectionBackoff(maximum: .seconds(2))
      .connect(host: "localhost", port: self.port)

    // Start an RPC to trigger creating a channel, it's a streaming RPC so that when the server is
    // killed, the client still has one active RPC and transitions to transient failure (rather than
    // idle if there were no active RPCs).
    let echo = Echo_EchoClient(channel: self.client, defaultCallOptions: self.callOptionsWithLogger)
    _ = echo.update { _ in }

    // Wait for the connection to be ready.
    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))

    // Now that we have a healthy connection, prepare for two transient failures:
    // 1. when the server has been killed, and
    // 2. when the client attempts to reconnect.
    self.connectionStateRecorder.expectChanges(3) { changes in
      XCTAssertEqual(changes, [
        Change(from: .ready, to: .transientFailure),
        Change(from: .transientFailure, to: .connecting),
        Change(from: .connecting, to: .transientFailure),
      ])
    }

    // Okay, kill the server!
    try server.close().wait()
    try self.serverGroup.syncShutdownGracefully()
    self.server = nil
    self.serverGroup = nil

    // Our connection should fail now.
    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))

    // Get ready for the new healthy connection.
    self.connectionStateRecorder.expectChanges(2) { changes in
      XCTAssertEqual(changes, [
        Change(from: .transientFailure, to: .connecting),
        Change(from: .connecting, to: .ready),
      ])
    }

    // This should succeed once we get a connection again.
    let get = echo.get(.with { $0.text = "hello" })

    // Start a new server.
    self.serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = self.makeServer()

    self.connectionStateRecorder.waitForExpectedChanges(timeout: .seconds(5))

    // The call should be able to succeed now.
    XCTAssertEqual(try get.status.map { $0.code }.wait(), .ok)

    try self.client.close().wait()
  }
}
