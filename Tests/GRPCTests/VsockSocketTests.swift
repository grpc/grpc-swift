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
import GRPC
import NIOPosix
import XCTest

class VsockSocketTests: GRPCTestCase {
  func testVsockSocket() throws {
    try XCTSkipUnless(self.vsockAvailable(), "Vsock unavailable")
    let group = NIOPosix.MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    // Setup a server.
    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(vsockAddress: .init(cid: .any, port: 31234))
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

    let channel = try GRPCChannelPool.with(
      target: .vsockAddress(.init(cid: .local, port: 31234)),
      transportSecurity: .plaintext,
      eventLoopGroup: group
    )
    defer {
      XCTAssertNoThrow(try channel.close().wait())
    }

    let client = Echo_EchoNIOClient(channel: channel)
    let resp = try client.get(Echo_EchoRequest(text: "Hello")).response.wait()
    XCTAssertEqual(resp.text, "Swift echo get: Hello")
  }

  private func vsockAvailable() -> Bool {
    let fd: CInt
    #if os(Linux)
    fd = socket(AF_VSOCK, CInt(SOCK_STREAM.rawValue), 0)
    #elseif canImport(Darwin)
    fd = socket(AF_VSOCK, SOCK_STREAM, 0)
    #else
    fd = -1
    #endif
    if fd == -1 { return false }
    precondition(close(fd) == 0)
    return true
  }
}
