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
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

class DebugChannelInitializerTests: GRPCTestCase {
  func testDebugChannelInitializerIsCalled() throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let serverDebugInitializerCalled = group.next().makePromise(of: Void.self)
    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withDebugChannelInitializer { channel in
        serverDebugInitializerCalled.succeed(())
        return channel.eventLoop.makeSucceededFuture(())
      }
      .bind(host: "localhost", port: 0)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    let clientDebugInitializerCalled = group.next().makePromise(of: Void.self)
    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .withDebugChannelInitializer { channel in
        clientDebugInitializerCalled.succeed(())
        return channel.eventLoop.makeSucceededFuture(())
      }
      .connect(host: "localhost", port: server.channel.localAddress!.port!)
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    let echo = Echo_EchoClient(channel: connection)
    // Make an RPC to trigger channel creation.
    let get = echo.get(.with { $0.text = "Hello!" })
    XCTAssertTrue(try get.status.map { $0.isOk }.wait())

    // Check the initializers were called.
    XCTAssertNoThrow(try clientDebugInitializerCalled.futureResult.wait())
    XCTAssertNoThrow(try serverDebugInitializerCalled.futureResult.wait())
  }
}
