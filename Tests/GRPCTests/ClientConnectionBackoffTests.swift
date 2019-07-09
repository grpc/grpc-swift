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

class ConnectivityStateCollectionDelegate: ConnectivityStateDelegate {
  var states: [ConnectivityState] = []

  func clearStates() -> [ConnectivityState] {
    defer {
      self.states = []
    }
    return self.states
  }

  var idleExpectation: XCTestExpectation?
  var connectingExpectation: XCTestExpectation?
  var readyExpectation: XCTestExpectation?
  var transientFailureExpectation: XCTestExpectation?
  var shutdownExpectation: XCTestExpectation?

  init(
    idle: XCTestExpectation? = nil,
    connecting: XCTestExpectation? = nil,
    ready: XCTestExpectation? = nil,
    transientFailure: XCTestExpectation? = nil,
    shutdown: XCTestExpectation? = nil
  ) {
    self.idleExpectation = idle
    self.connectingExpectation = connecting
    self.readyExpectation = ready
    self.transientFailureExpectation = transientFailure
    self.shutdownExpectation = shutdown
  }

  func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
    self.states.append(newState)

    switch newState {
    case .idle:
      self.idleExpectation?.fulfill()

    case .connecting:
      self.connectingExpectation?.fulfill()

    case .ready:
      self.readyExpectation?.fulfill()

    case .transientFailure:
      self.transientFailureExpectation?.fulfill()

    case .shutdown:
      self.shutdownExpectation?.fulfill()
    }
  }
}

class ClientConnectionBackoffTests: XCTestCase {
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

  func makeClientConfiguration() -> ClientConnection.Configuration {
    return .init(
      target: .hostAndPort("localhost", self.port),
      eventLoopGroup: self.clientGroup,
      connectivityStateDelegate: self.stateDelegate,
      connectionBackoff: ConnectionBackoff(maximumBackoff: 0.1))
  }

  func makeClientConnection(
    _ configuration: ClientConnection.Configuration
  ) -> ClientConnection {
    return ClientConnection(configuration: configuration)
  }

  func testClientConnectionFailsWithNoBackoff() throws {
    var configuration = self.makeClientConfiguration()
    configuration.connectionBackoff = nil

    let connectionShutdown = self.expectation(description: "client shutdown")
    self.stateDelegate.shutdownExpectation = connectionShutdown
    self.client = self.makeClientConnection(configuration)

    self.wait(for: [connectionShutdown], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.states, [.connecting, .shutdown])
  }

  func testClientEventuallyConnects() throws {
    let transientFailure = self.expectation(description: "connection transientFailure")
    let connectionReady = self.expectation(description: "connection ready")
    self.stateDelegate.transientFailureExpectation = transientFailure
    self.stateDelegate.readyExpectation = connectionReady

    // Start the client first.
    self.client = self.makeClientConnection(self.makeClientConfiguration())

    self.wait(for: [transientFailure], timeout: 1.0)

    self.server = self.makeServer()
    let serverStarted = self.expectation(description: "server started")
    self.server.assertSuccess(fulfill: serverStarted)

    self.wait(for: [serverStarted, connectionReady], timeout: 2.0, enforceOrder: true)
    XCTAssertEqual(self.stateDelegate.states, [.connecting, .transientFailure, .connecting, .ready])
  }

  func testClientEventuallyTimesOut() throws {
    let connectionShutdown = self.expectation(description: "connection shutdown")
    self.stateDelegate.shutdownExpectation = connectionShutdown
    self.client = self.makeClientConnection(self.makeClientConfiguration())

    self.wait(for: [connectionShutdown], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.states, [.connecting, .transientFailure, .connecting, .shutdown])
  }

  func testClientReconnectsAutomatically() throws {
    self.server = self.makeServer()
    let server = try self.server.wait()

    var configuration = self.makeClientConfiguration()
    configuration.connectionBackoff!.maximumBackoff = 2.0

    let connectionReady = self.expectation(description: "connection ready")
    let transientFailure = self.expectation(description: "connection transientFailure")
    self.stateDelegate.readyExpectation = connectionReady
    self.stateDelegate.transientFailureExpectation = transientFailure

    self.client = self.makeClientConnection(configuration)

    // Once the connection is ready we can kill the server.
    self.wait(for: [connectionReady], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.clearStates(), [.connecting, .ready])

    try server.close().wait()
    try self.serverGroup.syncShutdownGracefully()
    self.server = nil
    self.serverGroup = nil

    self.wait(for: [transientFailure], timeout: 1.0)
    XCTAssertEqual(self.stateDelegate.clearStates(), [.connecting, .transientFailure])

    // Replace the ready expectation (since it's already been fulfilled).
    let reconnectionReady = self.expectation(description: "(re)connection ready")
    self.stateDelegate.readyExpectation = reconnectionReady

    let echo = Echo_EchoServiceClient(connection: self.client)
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
