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
import EchoModel
import GRPC
import NIO
import XCTest

class ConnectionFailingTests: GRPCTestCase {
  func testStartRPCWhenChannelIsInTransientFailure() throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let waiter = RecordingConnectivityDelegate()
    let connection = ClientConnection.insecure(group: group)
      // We want to make sure we sit in transient failure for a long time.
      .withConnectionBackoff(initial: .hours(24))
      .withCallStartBehavior(.fastFailure)
      .withConnectivityStateDelegate(waiter)
      .connect(host: "http://unreachable.invalid", port: 0)
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    let echo = Echo_EchoClient(channel: connection)

    // Set our expectation.
    waiter.expectChanges(2) { changes in
      XCTAssertEqual(changes[0], Change(from: .idle, to: .connecting))
      XCTAssertEqual(changes[1], Change(from: .connecting, to: .transientFailure))
    }

    // This will trigger a connection attempt and subsequently fail.
    _ = echo.get(.with { $0.text = "cheddar" })

    // Wait for the changes.
    waiter.waitForExpectedChanges(timeout: .seconds(10))

    // Okay, now let's try another RPC. It should fail immediately with the connection error.
    let get = echo.get(.with { $0.text = "comté" })
    XCTAssertThrowsError(try get.response.wait())
    let status = try get.status.wait()
    XCTAssertEqual(status.code, .unavailable)
    // We can't say too much about the message here. It should contain details about the transient
    // failure error.
    XCTAssertNotNil(status.message)
    XCTAssertTrue(status.message?.contains("unreachable.invalid") ?? false)
  }
}
