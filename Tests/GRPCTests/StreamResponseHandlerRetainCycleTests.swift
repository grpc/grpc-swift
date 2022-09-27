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
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

final class StreamResponseHandlerRetainCycleTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var client: ClientConnection!

  var echo: Echo_EchoNIOClient!

  override func setUp() {
    super.setUp()
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.server = try! Server.insecure(group: self.group)
      .withServiceProviders([EchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "localhost", port: 0)
      .wait()

    self.client = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server.channel.localAddress!.port!)

    self.echo = Echo_EchoNIOClient(
      channel: self.client,
      defaultCallOptions: CallOptions(logger: self.clientLogger)
    )
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.close().wait())
    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func testHandlerClosureIsReleasedOnceStreamEnds() {
    final class Counter {
      private let lock = NIOLock()
      private var _value = 0

      func increment() {
        self.lock.withLock {
          self._value += 1
        }
      }

      var value: Int {
        return self.lock.withLock {
          self._value
        }
      }
    }

    var counter = Counter()
    XCTAssertTrue(isKnownUniquelyReferenced(&counter))
    let get = self.echo.update { [capturedCounter = counter] _ in
      capturedCounter.increment()
    }
    XCTAssertFalse(isKnownUniquelyReferenced(&counter))

    get.sendMessage(.init(text: "hello world"), promise: nil)
    XCTAssertFalse(isKnownUniquelyReferenced(&counter))
    XCTAssertNoThrow(try get.sendEnd().wait())
    XCTAssertNoThrow(try get.status.wait())
    XCTAssertEqual(counter.value, 1)
    XCTAssertTrue(isKnownUniquelyReferenced(&counter))
  }
}
