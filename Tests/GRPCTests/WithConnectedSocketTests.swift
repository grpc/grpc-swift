/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

class WithConnectedSockettests: GRPCTestCase {
  func testWithConnectedSocket() throws {
    let group = NIOPosix.MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let path = "/tmp/grpc-\(getpid()).sock"
    // Setup a server.
    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(unixDomainSocketPath: path)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    #if os(Linux)
    let sockStream = CInt(SOCK_STREAM.rawValue)
    #else
    let sockStream = SOCK_STREAM
    #endif
    let clientSocket = socket(AF_UNIX, sockStream, 0)

    XCTAssert(clientSocket != -1)
    let addr = try SocketAddress(unixDomainSocketPath: path)
    addr.withSockAddr { addr, size in
      let ret = connect(clientSocket, addr, UInt32(size))
      XCTAssert(ret != -1)
    }
    let flags = fcntl(clientSocket, F_GETFL, 0)
    XCTAssert(flags != -1)
    XCTAssert(fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK) == 0)

    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      .withConnectedSocket(clientSocket)
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    let client = Echo_EchoNIOClient(channel: connection)
    let resp = try client.get(Echo_EchoRequest(text: "Hello")).response.wait()
    XCTAssertEqual(resp.text, "Swift echo get: Hello")
  }
}
