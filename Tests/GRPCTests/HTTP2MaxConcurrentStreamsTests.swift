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
import NIOCore
import NIOHTTP2
import NIOPosix
import XCTest

@testable import GRPC

class HTTP2MaxConcurrentStreamsTests: GRPCTestCase {
  enum Constants {
    static let testTimeout: TimeInterval = 10

    static let defaultMaxNumberOfConcurrentStreams =
      nioDefaultSettings.first(where: { $0.parameter == .maxConcurrentStreams })!.value

    static let testNumberOfConcurrentStreams: Int = defaultMaxNumberOfConcurrentStreams + 20
  }

  func testHTTP2MaxConcurrentStreamsSetting() {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }

    let server = try! Server.insecure(group: eventLoopGroup)
      .withLogger(self.serverLogger)
      .withHTTPMaxConcurrentStreams(Constants.testNumberOfConcurrentStreams)
      .withServiceProviders([EchoProvider()])
      .bind(host: "localhost", port: 0)
      .wait()

    defer { XCTAssertNoThrow(try server.initiateGracefulShutdown().wait()) }

    let clientConnection = ClientConnection.insecure(group: eventLoopGroup)
      .withBackgroundActivityLogger(self.clientLogger)
      .connect(host: "localhost", port: server.channel.localAddress!.port!)

    defer { XCTAssertNoThrow(try clientConnection.close().wait()) }

    let echoClient = Echo_EchoNIOClient(
      channel: clientConnection,
      defaultCallOptions: CallOptions(logger: self.clientLogger)
    )

    var clientStreamingCalls =
      (0 ..< Constants.testNumberOfConcurrentStreams)
      .map { _ in echoClient.collect() }

    let allMessagesSentExpectation = self.expectation(description: "all messages sent")

    let sendMessageFutures =
      clientStreamingCalls
      .map { $0.sendMessage(.with { $0.text = "Hi!" }) }

    EventLoopFuture<Void>
      .whenAllSucceed(sendMessageFutures, on: eventLoopGroup.next())
      .assertSuccess(fulfill: allMessagesSentExpectation)

    self.wait(for: [allMessagesSentExpectation], timeout: Constants.testTimeout)

    let lastCall = clientStreamingCalls.popLast()!

    let lastCallCompletedExpectation = self.expectation(description: "last call completed")
    _ = lastCall.sendEnd()

    lastCall.status.assertSuccess(fulfill: lastCallCompletedExpectation)

    self.wait(for: [lastCallCompletedExpectation], timeout: Constants.testTimeout)

    let allCallsCompletedExpectation = self.expectation(description: "all calls completed")
    let endFutures = clientStreamingCalls.map { $0.sendEnd() }

    EventLoopFuture<Void>
      .whenAllSucceed(endFutures, on: eventLoopGroup.next())
      .assertSuccess(fulfill: allCallsCompletedExpectation)

    self.wait(for: [allCallsCompletedExpectation], timeout: Constants.testTimeout)
  }
}
