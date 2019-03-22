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
@testable import SwiftGRPC
import XCTest

class ClientTimeoutTests: BasicEchoTestCase {
  override var defaultTimeout: TimeInterval { return 0.1 }
}

extension ClientTimeoutTests {
  func testClientStreamingTimeoutBeforeSending() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.deadlineExceeded, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    Thread.sleep(forTimeInterval: 0.2)

    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in
      XCTAssertEqual(.unknown, $0 as! CallError)
      sendExpectation.fulfill()
    }
    call.waitForSendOperationsToFinish()

    do {
      let result = try call.closeAndReceive()
      XCTFail("should have thrown, received \(result) instead")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testClientStreamingTimeoutAfterSending() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.collect { callResult in
      XCTAssertEqual(.deadlineExceeded, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    let sendExpectation = expectation(description: "send completion handler 1 called")
    try! call.send(Echo_EchoRequest(text: "foo")) { [sendExpectation] in XCTAssertNil($0); sendExpectation.fulfill() }
    call.waitForSendOperationsToFinish()

    Thread.sleep(forTimeInterval: 0.2)

    do {
      let result = try call.closeAndReceive()
      XCTFail("should have thrown, received \(result) instead")
    } catch let receiveError {
      XCTAssertEqual(.unknown, (receiveError as! RPCError).callResult!.statusCode)
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testBidirectionalStreamingTimeoutPassedToReceiveMethod() {
    let completionHandlerExpectation = expectation(description: "final completion handler called")
    let call = try! client.update { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      completionHandlerExpectation.fulfill()
    }

    do {
      let result = try call.receive(timeout: .now() + .milliseconds(10))
      XCTFail("should have thrown, received \(String(describing: result)) instead")
    } catch let receiveError {
      if case .timedOut = receiveError as! RPCError {
        // This is the expected case - we need to formulate this as an if statement to use case-based pattern matching.
      } else {
        XCTFail("received error \(receiveError) instead of .timedOut")
      }
    }

    try! call.closeSend()

    waitForExpectations(timeout: defaultTimeout)
  }

  // FIXME(danielalm): Add support for setting a maximum timeout on the server, to prevent DoS attacks where clients
  // start a ton of calls, but never finish them (i.e. essentially leaking a connection on the server side).
}
