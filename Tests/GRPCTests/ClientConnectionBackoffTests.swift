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
import EchoModel
import EchoImplementation
import NIO
import XCTest
import NIOConcurrencyHelpers

class ConnectivityStateCollectionDelegate: ConnectivityStateDelegate {
  private var _states: [ConnectivityState] = []
  private var lock = Lock()

  var states: [ConnectivityState] {
    get {
      return self.lock.withLock {
        return self._states
      }
    }
  }

  func clearStates() -> [ConnectivityState] {
    self.lock.lock()
    defer {
      self._states.removeAll()
      self.lock.unlock()
    }
    return self._states
  }

  private var _expectations: [ConnectivityState: XCTestExpectation] = [:]

  var expectations: [ConnectivityState: XCTestExpectation] {
    get {
      return self.lock.withLock {
       self._expectations
      }
    }
    set {
      self.lock.withLockVoid {
        self._expectations = newValue
      }
    }
  }

  init(
    idle: XCTestExpectation? = nil,
    connecting: XCTestExpectation? = nil,
    ready: XCTestExpectation? = nil,
    transientFailure: XCTestExpectation? = nil,
    shutdown: XCTestExpectation? = nil
  ) {
    self.expectations[.idle] = idle
    self.expectations[.connecting] = connecting
    self.expectations[.ready] = ready
    self.expectations[.transientFailure] = transientFailure
    self.expectations[.shutdown] = shutdown
  }

  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
    self.lock.withLockVoid {
      self._states.append(newState)
      self._expectations[newState]?.fulfill()
    }
  }
}

class ClientConnectionBackoffTests: GRPCTestCase {
  let port = 8080

  var client: ClientConnection!
  var server: EventLoopFuture<Server>!

  var serverGroup: EventLoopGroup!
  var clientGroup: EventLoopGroup!

  var stateDelegate = ConnectivityStateCollectionDelegate()

  override func setUp() {
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
  }

  func makeServer() -> EventLoopFuture<Server> {
    let configuration = Server.Configuration(
      target: .hostAndPort("localhost", self.port),
      eventLoopGroup: self.serverGroup,
      serviceProviders: [EchoProvider()])

    return Server.start(configuration: configuration)
  }

  func connectionBuilder() -> ClientConnection.Builder {
    return ClientConnection.insecure(group: self.clientGroup)
      .withConnectivityStateDelegate(self.stateDelegate)
      .withConnectionBackoff(maximum: .milliseconds(100))
      .withConnectionTimeout(minimum: .milliseconds(100))
  }

  func testClientConnectionFailsWithNoBackoff() throws {
    let connectionShutdown = self.expectation(description: "client shutdown")
    self.stateDelegate.expectations[.shutdown] = connectionShutdown
    self.client = self.connectionBuilder()
      .withConnectionReestablishment(enabled: false)
      .connect(host: "localhost", port: self.port)

    self.wait(for: [connectionShutdown], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.states, [.connecting, .shutdown])
  }

  func testClientEventuallyConnects() throws {
    let transientFailure = self.expectation(description: "connection transientFailure")
    let connectionReady = self.expectation(description: "connection ready")
    self.stateDelegate.expectations[.transientFailure] = transientFailure
    self.stateDelegate.expectations[.ready] = connectionReady

    // Start the client first.
    self.client = self.connectionBuilder()
      .connect(host: "localhost", port: self.port)

    self.wait(for: [transientFailure], timeout: 1.0)
    self.stateDelegate.expectations[.transientFailure] = nil
    XCTAssertEqual(self.stateDelegate.clearStates(), [.connecting, .transientFailure])

    self.server = self.makeServer()
    let serverStarted = self.expectation(description: "server started")
    self.server.assertSuccess(fulfill: serverStarted)

    self.wait(for: [serverStarted, connectionReady], timeout: 2.0, enforceOrder: true)
    // We can have other transient failures and connection attempts while the server starts, we only
    // care about the last two.
    XCTAssertEqual(self.stateDelegate.states.suffix(2), [.connecting, .ready])
  }

  func testClientReconnectsAutomatically() throws {
    // Wait for the server to start.
    self.server = self.makeServer()
    let server = try self.server.wait()

    // Prepare the delegate so it expects the connection to hit `.ready`.
    let connectionReady = self.expectation(description: "connection ready")
    self.stateDelegate.expectations[.ready] = connectionReady

    // Configure the client backoff to have a short backoff.
    self.client = self.connectionBuilder()
      .withConnectionBackoff(maximum: .seconds(2))
      .connect(host: "localhost", port: self.port)

    // Wait for the connection to be ready.
    self.wait(for: [connectionReady], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.clearStates(), [.connecting, .ready])

    // Now that we have a healthy connectiony, prepare for two transient failures:
    // 1. when the server has been killed, and
    // 2. when the client attempts to reconnect.
    let transientFailure = self.expectation(description: "connection transientFailure")
    transientFailure.expectedFulfillmentCount = 2
    self.stateDelegate.expectations[.transientFailure] = transientFailure
    self.stateDelegate.expectations[.ready] = nil

    // Okay, kill the server!
    try server.close().wait()
    try self.serverGroup.syncShutdownGracefully()
    self.server = nil
    self.serverGroup = nil

    // Our connection should fail now.
    self.wait(for: [transientFailure], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.clearStates(), [.transientFailure, .connecting, .transientFailure])
    self.stateDelegate.expectations[.transientFailure] = nil

    // Prepare an expectation for a new healthy connection.
    let reconnectionReady = self.expectation(description: "(re)connection ready")
    self.stateDelegate.expectations[.ready] = reconnectionReady

    let echo = Echo_EchoClient(channel: self.client)
    // This should succeed once we get a connection again.
    let get = echo.get(.with { $0.text = "hello" })

    // Start a new server.
    self.serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = self.makeServer()

    self.wait(for: [reconnectionReady], timeout: 2.0)
    XCTAssertEqual(self.stateDelegate.clearStates(), [.connecting, .ready])

    // The call should be able to succeed now.
    XCTAssertEqual(try get.status.map { $0.code }.wait(), .ok)

    try self.client.close().wait()
    XCTAssertEqual(self.stateDelegate.clearStates(), [.shutdown])
  }
}
