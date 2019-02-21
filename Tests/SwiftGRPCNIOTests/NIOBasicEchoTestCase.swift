/*
 * Copyright 2018, gRPC Authors All rights reserved.
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
import Dispatch
import Foundation
import NIO
@testable import SwiftGRPCNIO
import XCTest

extension Echo_EchoRequest {
  init(text: String) {
    self.text = text
  }
}

extension Echo_EchoResponse {
  init(text: String) {
    self.text = text
  }
}

class NIOBasicEchoTestCase: XCTestCase {
  var defaultTestTimeout: TimeInterval = 1.0

  var serverEventLoopGroup: EventLoopGroup!
  var server: GRPCServer!

  var clientEventLoopGroup: EventLoopGroup!
  var client: Echo_EchoService_NIOClient!

  override func setUp() {
    super.setUp()

    self.serverEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.server = try! GRPCServer.start(
      hostname: "localhost", port: 5050, eventLoopGroup: self.serverEventLoopGroup, serviceProviders: [EchoProviderNIO()])
      .wait()

    self.clientEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    self.client = try! GRPCClient.start(
      host: "localhost", port: 5050, eventLoopGroup: self.clientEventLoopGroup)
      .map { Echo_EchoService_NIOClient(client: $0, defaultCallOptions: CallOptions(timeout: try! .seconds(5))) }
      .wait()
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.client.client.close().wait())
    XCTAssertNoThrow(try self.clientEventLoopGroup.syncShutdownGracefully())
    self.clientEventLoopGroup = nil
    self.client = nil

    XCTAssertNoThrow(try self.server.close().wait())
    XCTAssertNoThrow(try self.serverEventLoopGroup.syncShutdownGracefully())
    self.serverEventLoopGroup = nil
    self.server = nil

    super.tearDown()
  }
}
