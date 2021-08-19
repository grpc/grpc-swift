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
import NIOCore
import NIOPosix
import XCTest

class ServerQuiescingTests: GRPCTestCase {
  func testServerQuiescing() throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer {
      assertThat(try group.syncShutdownGracefully(), .doesNotThrow())
    }

    let server = try Server.insecure(group: group)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    let connectivityStateDelegate = RecordingConnectivityDelegate()
    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .withErrorDelegate(LoggingClientErrorDelegate())
      .withConnectivityStateDelegate(connectivityStateDelegate)
      .connect(host: "127.0.0.1", port: server.channel.localAddress!.port!)
    defer {
      assertThat(try connection.close().wait(), .doesNotThrow())
    }

    let echo = Echo_EchoClient(channel: connection)

    // Expect the connection to setup as normal.
    connectivityStateDelegate.expectChanges(2) { changes in
      XCTAssertEqual(changes[0], Change(from: .idle, to: .connecting))
      XCTAssertEqual(changes[1], Change(from: .connecting, to: .ready))
    }

    // Fire up a handful of client streaming RPCs, this will start the connection.
    let rpcs = (0 ..< 5).map { _ in
      echo.collect()
    }

    // Wait for the connectivity changes.
    connectivityStateDelegate.waitForExpectedChanges(timeout: .seconds(5))

    // Wait for the response metadata so both peers know about all RPCs.
    for rpc in rpcs {
      assertThat(try rpc.initialMetadata.wait(), .doesNotThrow())
    }

    // Start shutting down the server.
    let serverShutdown = server.initiateGracefulShutdown()

    // We should observe that we're quiescing now: this is a signal to not start any new RPCs.
    connectivityStateDelegate.waitForQuiescing(timeout: .seconds(5))

    // Queue up the expected change back to idle (i.e. when the connection is quiesced).
    connectivityStateDelegate.expectChange {
      XCTAssertEqual($0, Change(from: .ready, to: .idle))
    }

    // Finish each RPC.
    for (index, rpc) in rpcs.enumerated() {
      assertThat(try rpc.sendMessage(.with { $0.text = "\(index)" }).wait(), .doesNotThrow())
      assertThat(try rpc.sendEnd().wait(), .doesNotThrow())
      assertThat(try rpc.response.wait(), .is(.with { $0.text = "Swift echo collect: \(index)" }))
    }

    // All RPCs are done, the connection should drop back to idle.
    connectivityStateDelegate.waitForExpectedChanges(timeout: .seconds(5))

    // The server should be shutdown now.
    assertThat(try serverShutdown.wait(), .doesNotThrow())
  }
}
