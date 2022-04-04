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
@testable import NIOPosix
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

    let socket = try Socket(protocolFamily: .unix, type: .stream)
    XCTAssert(try socket.connect(to: .init(unixDomainSocketPath: path)))

    // Setup a connection. We'll add a handler to drop all reads, this is somewhat equivalent to
    // simulating bad network conditions and allows us to setup a connection and have our keepalive
    // timeout expire.
    let connection = ClientConnection.insecure(group: group)
      .withBackgroundActivityLogger(self.clientLogger)
      // See above comments for why we need this.
      .withCallStartBehavior(.fastFailure)
      .withKeepalive(.init(interval: .seconds(1), timeout: .milliseconds(100)))
      .withDebugChannelInitializer { channel in
        channel.pipeline.addHandler(ReadDroppingHandler(), position: .first)
      }
      .withConnectedSocket(try socket.takeDescriptorOwnership())
    defer {
      XCTAssertNoThrow(try connection.close().wait())
    }

    let client = Echo_EchoClient(channel: connection)
    let get = client.get(.with { $0.text = "Hello" })
    XCTAssertThrowsError(try get.response.wait())
    XCTAssertEqual(try get.status.map { $0.code }.wait(), .unavailable)
  }

  class ReadDroppingHandler: ChannelDuplexHandler {
    typealias InboundIn = Any
    typealias OutboundIn = Any

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {}
  }
}
