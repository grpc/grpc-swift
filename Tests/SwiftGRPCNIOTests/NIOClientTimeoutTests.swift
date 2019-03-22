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
import SwiftGRPCNIO
import NIO
import XCTest

class NIOClientTimeoutTests: NIOBasicEchoTestCase {
  let optionsWithShortTimeout = CallOptions(timeout: try! GRPCTimeout.milliseconds(10))
  let moreThanShortTimeout: TimeInterval = 0.011

  static var allTests: [(String, (NIOClientTimeoutTests) -> () throws -> Void)] {
    return [
      ("testUnaryTimeoutAfterSending", testUnaryTimeoutAfterSending),
      ("testServerStreamingTimeoutAfterSending", testServerStreamingTimeoutAfterSending),
      ("testClientStreamingTimeoutBeforeSending", testClientStreamingTimeoutBeforeSending),
      ("testClientStreamingTimeoutAfterSending", testClientStreamingTimeoutAfterSending),
      ("testBidirectionalStreamingTimeoutBeforeSending", testBidirectionalStreamingTimeoutBeforeSending),
      // This test tends to crash randomly on Linux, so it is disabled there for now.
      //("testBidirectionalStreamingTimeoutAfterSending", testBidirectionalStreamingTimeoutAfterSending),
    ]
  }

  private func expectDeadlineExceeded(forStatus status: EventLoopFuture<GRPCStatus>) {
    let statusExpectation = self.expectation(description: "status received")

    status.whenSuccess { status in
      XCTAssertEqual(status.code, .deadlineExceeded)
      statusExpectation.fulfill()
    }

    status.whenFailure { error in
      XCTFail("unexpectedly received error for status: \(error)")
    }
  }

  private func expectDeadlineExceeded(forResponse response: EventLoopFuture<Echo_EchoResponse>) {
    let responseExpectation = self.expectation(description: "response received")

    response.whenFailure { error in
      XCTAssertEqual((error as? GRPCStatus)?.code, .deadlineExceeded)
      responseExpectation.fulfill()
    }

    response.whenSuccess { response in
      XCTFail("response received after deadline")
    }
  }
}

extension NIOClientTimeoutTests {
  func testUnaryTimeoutAfterSending() {
    // The request gets fired on call creation, so we need a very short timeout.
    let callOptions = CallOptions(timeout: try! .milliseconds(1))
    let call = client.get(Echo_EchoRequest(text: "foo"), callOptions: callOptions)

    self.expectDeadlineExceeded(forStatus: call.status)
    self.expectDeadlineExceeded(forResponse: call.response)

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testServerStreamingTimeoutAfterSending() {
    // The request gets fired on call creation, so we need a very short timeout.
    let callOptions = CallOptions(timeout: try! .milliseconds(1))
    let call = client.expand(Echo_EchoRequest(text: "foo bar baz"), callOptions: callOptions) { _ in }

    self.expectDeadlineExceeded(forStatus: call.status)

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testClientStreamingTimeoutBeforeSending() {
    let call = client.collect(callOptions: optionsWithShortTimeout)

    self.expectDeadlineExceeded(forStatus: call.status)
    self.expectDeadlineExceeded(forResponse: call.response)

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testClientStreamingTimeoutAfterSending() {
    let call = client.collect(callOptions: optionsWithShortTimeout)

    self.expectDeadlineExceeded(forStatus: call.status)
    self.expectDeadlineExceeded(forResponse: call.response)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)

    // Timeout before sending `.end`
    Thread.sleep(forTimeInterval: moreThanShortTimeout)
    call.sendEnd(promise: nil)

    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testBidirectionalStreamingTimeoutBeforeSending() {
    let call = client.update(callOptions: optionsWithShortTimeout)  { _ in }

    self.expectDeadlineExceeded(forStatus: call.status)

    Thread.sleep(forTimeInterval: moreThanShortTimeout)
    waitForExpectations(timeout: defaultTestTimeout)
  }

  func testBidirectionalStreamingTimeoutAfterSending() {
    let call = client.update(callOptions: optionsWithShortTimeout) { _ in }

    self.expectDeadlineExceeded(forStatus: call.status)

    call.sendMessage(Echo_EchoRequest(text: "foo"), promise: nil)

    // Timeout before sending `.end`
    Thread.sleep(forTimeInterval: moreThanShortTimeout)
    call.sendEnd(promise: nil)

    waitForExpectations(timeout: defaultTestTimeout)
  }
}
