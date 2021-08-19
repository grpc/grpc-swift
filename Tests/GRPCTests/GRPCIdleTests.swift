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
@testable import GRPC
import NIOCore
import NIOPosix
import XCTest

class GRPCIdleTests: GRPCTestCase {
  func testClientIdleTimeout() {
    XCTAssertNoThrow(
      try self
        .doTestIdleTimeout(serverIdle: .minutes(5), clientIdle: .milliseconds(100))
    )
  }

  func testServerIdleTimeout() throws {
    XCTAssertNoThrow(
      try self
        .doTestIdleTimeout(serverIdle: .milliseconds(100), clientIdle: .minutes(5))
    )
  }

  func doTestIdleTimeout(serverIdle: TimeAmount, clientIdle: TimeAmount) throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    // Setup a server.
    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withConnectionIdleTimeout(serverIdle)
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    // Setup a state change recorder for the client.
    let stateRecorder = RecordingConnectivityDelegate()
    stateRecorder.expectChanges(3) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .ready),
        Change(from: .ready, to: .idle),
      ])
    }

    // Setup a connection.
    let connection = ClientConnection.insecure(group: group)
      .withConnectivityStateDelegate(stateRecorder)
      .withConnectionIdleTimeout(clientIdle)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: server.channel.localAddress!.port!)
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    let client = Echo_EchoClient(channel: connection)

    // Make a call; this will trigger channel creation.
    let get = client.get(.with { $0.text = "ignored" })
    let status = try get.status.wait()
    XCTAssertEqual(status.code, .ok)

    // Now wait for the state changes.
    stateRecorder.waitForExpectedChanges(timeout: .seconds(10))
  }
}
