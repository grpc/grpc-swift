/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
@testable import GRPC
import EchoModel
import NIO
import XCTest

class ClientTimeoutTests: GRPCTestCase {
  var channel: EmbeddedChannel!
  var client: Echo_EchoClient!

  let timeout = TimeAmount.milliseconds(100)
  var callOptions: CallOptions {
    // We use a deadline here because internally we convert timeouts into deadlines by diffing
    // with `DispatchTime.now()`. We therefore need the deadline to be known in advance. Note we
    // use zero because `EmbeddedEventLoop`s time starts at zero.
    var options = self.callOptionsWithLogger
    options.timeLimit = .deadline(.uptimeNanoseconds(0) + timeout)
    return options
  }

  // Note: this is not related to the call timeout since we're using an EmbeddedChannel. We require
  // this in case the timeout doesn't work.
  let testTimeout: TimeInterval = 0.1

  override func setUp() {
    super.setUp()

    let connection = EmbeddedGRPCChannel(logger: self.clientLogger)
    XCTAssertNoThrow(try connection.embeddedChannel.connect(to: SocketAddress(unixDomainSocketPath: "/foo")))
    let client = Echo_EchoClient(channel: connection, defaultCallOptions: self.callOptions)

    self.channel = connection.embeddedChannel
    self.client = client
  }

  override func tearDown() {
    XCTAssertNoThrow(try self.channel.finish())
    super.tearDown()
  }

  func assertRPCTimedOut(_ response: EventLoopFuture<Echo_EchoResponse>, expectation: XCTestExpectation) {
    response.whenComplete { result in
      switch result {
      case .success(let response):
        XCTFail("unexpected response: \(response)")
      case .failure(let error):
        XCTAssertTrue(error is GRPCError.RPCTimedOut)
      }
      expectation.fulfill()
    }
  }

  func assertDeadlineExceeded(_ status: EventLoopFuture<GRPCStatus>, expectation: XCTestExpectation) {
    status.whenComplete { result in
      switch result {
      case .success(let status):
        XCTAssertEqual(status.code, .deadlineExceeded)
      case .failure(let error):
        XCTFail("unexpected error: \(error)")
      }
      expectation.fulfill()
    }
  }

  func testUnaryTimeoutAfterSending() throws {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = self.client.get(Echo_EchoRequest(text: "foo"))
    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testServerStreamingTimeoutAfterSending() throws {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = client.expand(Echo_EchoRequest(text: "foo bar baz")) { _ in }
    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testClientStreamingTimeoutBeforeSending() throws {
    let responseExpectation = self.expectation(description: "response fulfilled")
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = client.collect()
    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertRPCTimedOut(call.response, expectation: responseExpectation)
    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [responseExpectation, statusExpectation], timeout: self.testTimeout)
  }

  func testClientStreamingTimeoutAfterSending() throws {
    let responseExpectation = self.expectation(description: "response fulfilled")
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = client.collect()

    self.assertRPCTimedOut(call.response, expectation: responseExpectation)
    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)
    call.sendEnd(promise: nil)
    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.wait(for: [responseExpectation, statusExpectation], timeout: 1.0)
  }

  func testBidirectionalStreamingTimeoutBeforeSending() {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = client.update { _ in }

    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)
    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }

  func testBidirectionalStreamingTimeoutAfterSending() {
    let statusExpectation = self.expectation(description: "status fulfilled")

    let call = client.update { _ in }

    self.assertDeadlineExceeded(call.status, expectation: statusExpectation)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)
    call.sendEnd(promise: nil)
    channel.embeddedEventLoop.advanceTime(by: self.timeout)

    self.wait(for: [statusExpectation], timeout: self.testTimeout)
  }
}
