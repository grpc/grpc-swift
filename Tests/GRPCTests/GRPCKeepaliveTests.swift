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
import NIO
import XCTest

class GRPCClientKeepaliveTests: GRPCTestCase {
  func testKeepaliveTimeoutFiresBeforeConnectionIsReady() throws {
    // This test relates to https://github.com/grpc/grpc-swift/issues/949
    //
    // When a stream is created, a ping may be sent on the connection. If a ping is sent we then
    // schedule a task for some time in the future to close the connection (if we don't receive the
    // ping ack in the meantime).
    //
    // The task to close actually fires an event which is picked up by the idle handler; this will
    // tell the connection manager to idle the connection. However, the connection manager only
    // tolerates being idled from the ready state. Since we protect from idling multiple times in
    // the handler we must be in a state where we have connection but are not yet ready (i.e.
    // channel active has fired but we have not seen the initial settings frame). To be in this
    // state the user must be using the 'fastFailure' call start behaviour (if this is not the case
    // then no channel will be vended until we reach the ready state, so it would not be possible
    // to create the stream).
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    // Setup a server.
    let server = try Server.insecure(group: group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()
    defer {
      XCTAssertNoThrow(try server.close().wait())
    }

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
      .connect(host: "localhost", port: server.channel.localAddress!.port!)
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
