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
import NIOCore
import NIOPosix
import XCTest

class CallStartBehaviorTests: GRPCTestCase {
  func testFastFailure() {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    // If the policy was 'waitsForConnectivity' we'd continue attempting to connect with backoff
    // and the RPC wouldn't complete until we call shutdown (because we're not setting a timeout).
    let channel = ClientConnection.insecure(group: group)
      .withCallStartBehavior(.fastFailure)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "http://unreachable.invalid", port: 0)
    defer {
      XCTAssertNoThrow(try channel.close().wait())
    }

    let echo = Echo_EchoNIOClient(channel: channel, defaultCallOptions: self.callOptionsWithLogger)
    let get = echo.get(.with { $0.text = "Is anyone out there?" })

    XCTAssertThrowsError(try get.response.wait())
    XCTAssertNoThrow(try get.status.wait())
  }
}
