/*
 * Copyright 2021, gRPC Authors All rights reserved.
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

final class HTTP2ConnectionDelegateTests: GRPCTestCase {
  private var group: EventLoopGroup!
  private var server: Server!
  private var connection: ClientConnection!
  private let queue = DispatchQueue(label: "io.grpc.testing")

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    self.server = try! Server.insecure(group: self.group)
      .withLogger(self.serverLogger)
      .withServiceProviders([EchoProvider()])
      .bind(host: "127.0.0.1", port: 0)
      .wait()

    self.connection = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      // The http/2 delegate is internal but uses the same queue as the connectivity state delegate,
      // so this looks odd but is fine.
      .withConnectivityStateDelegate(nil, executingOn: self.queue)
      .connect(host: "127.0.0.1", port: self.server!.channel.localAddress!.port!)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.connection.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func testDelegate() {
    let http2Delegate = RecordingHTTP2Delegate()
    self.connection.connectivity.http2Delegate = http2Delegate

    let echo = Echo_EchoClient(channel: self.connection)

    // Fire off a handful of RPCs.
    for _ in 0 ..< 10 {
      let get = echo.get(.with { $0.text = "" })
      XCTAssertNoThrow(try get.status.wait())
    }

    // 10 RPCs, 10 streams closed.
    XCTAssertEqual(self.queue.sync { http2Delegate.streamsClosed }, 10)
    XCTAssertEqual(self.queue.sync { http2Delegate.maxConcurrentStreamsChanges }, [100])
  }
}
