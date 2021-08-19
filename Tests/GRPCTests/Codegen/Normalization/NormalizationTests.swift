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

import GRPC
import NIOCore
import NIOPosix
import XCTest

/// These tests validate that:
/// - we can compile generated code for functions with same (case-insensitive) name (providing they
///   are generated with 'KeepMethodCasing=true')
/// - the right client function calls the server function with the expected casing.
final class NormalizationTests: GRPCTestCase {
  var group: EventLoopGroup!
  var server: Server!
  var channel: ClientConnection!

  override func setUp() {
    super.setUp()

    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    self.server = try! Server.insecure(group: self.group)
      .withLogger(self.serverLogger)
      .withServiceProviders([NormalizationProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    self.channel = ClientConnection.insecure(group: self.group)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: self.server.channel.localAddress!.port!)
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.close().wait())
    XCTAssertNoThrow(try self.server.initiateGracefulShutdown().wait())
    XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    super.tearDown()
  }

  func testUnary() throws {
    let client = Normalization_NormalizationClient(channel: channel)

    let unary1 = client.unary(.init())
    let response1 = try unary1.response.wait()
    XCTAssert(response1.functionName.starts(with: "unary"))

    let unary2 = client.Unary(.init())
    let response2 = try unary2.response.wait()
    XCTAssert(response2.functionName.starts(with: "Unary"))
  }

  func testClientStreaming() throws {
    let client = Normalization_NormalizationClient(channel: channel)

    let clientStreaming1 = client.clientStreaming()
    clientStreaming1.sendEnd(promise: nil)
    let response1 = try clientStreaming1.response.wait()
    XCTAssert(response1.functionName.starts(with: "clientStreaming"))

    let clientStreaming2 = client.ClientStreaming()
    clientStreaming2.sendEnd(promise: nil)
    let response2 = try clientStreaming2.response.wait()
    XCTAssert(response2.functionName.starts(with: "ClientStreaming"))
  }

  func testServerStreaming() throws {
    let client = Normalization_NormalizationClient(channel: channel)

    let serverStreaming1 = client.serverStreaming(.init()) {
      XCTAssert($0.functionName.starts(with: "serverStreaming"))
    }
    XCTAssertEqual(try serverStreaming1.status.wait(), .ok)

    let serverStreaming2 = client.ServerStreaming(.init()) {
      XCTAssert($0.functionName.starts(with: "ServerStreaming"))
    }
    XCTAssertEqual(try serverStreaming2.status.wait(), .ok)
  }

  func testBidirectionalStreaming() throws {
    let client = Normalization_NormalizationClient(channel: channel)

    let bidirectionalStreaming1 = client.bidirectionalStreaming {
      XCTAssert($0.functionName.starts(with: "bidirectionalStreaming"))
    }
    bidirectionalStreaming1.sendEnd(promise: nil)
    XCTAssertEqual(try bidirectionalStreaming1.status.wait(), .ok)

    let bidirectionalStreaming2 = client.BidirectionalStreaming {
      XCTAssert($0.functionName.starts(with: "BidirectionalStreaming"))
    }
    bidirectionalStreaming2.sendEnd(promise: nil)
    XCTAssertEqual(try bidirectionalStreaming2.status.wait(), .ok)
  }
}
