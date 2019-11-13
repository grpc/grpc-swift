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

class AsyncClientTests: BasicEchoTestCase {
  // Using `TimingOutEchoProvider` gives us enough time to release the client before we can expect a result.
  override func makeProvider() -> Echo_EchoProvider { return TimingOutEchoProvider() }

  static var allTests: [(String, (AsyncClientTests) -> () throws -> Void)] {
    return [
      ("testAsyncUnaryRetainsClientUntilCallFinished", testAsyncUnaryRetainsClientUntilCallFinished),
      ("testClientStreamingRetainsClientUntilCallFinished", testClientStreamingRetainsClientUntilCallFinished),
      ("testServerStreamingRetainsClientUntilCallFinished", testServerStreamingRetainsClientUntilCallFinished),
      ("testBidiStreamingRetainsClientUntilCallFinished", testBidiStreamingRetainsClientUntilCallFinished),
    ]
  }
}

extension AsyncClientTests {
  func testAsyncUnaryRetainsClientUntilCallFinished() {
    let completionHandlerExpectation = expectation(description: "completion handler called")
    _ = try! client.get(Echo_EchoRequest(text: "foo")) { response, result in
      XCTAssertEqual("", response?.text)
      XCTAssertEqual(.ok, result.statusCode)
      completionHandlerExpectation.fulfill()
    }
    // The call should complete even when the client and call are not retained.
    client = nil

    waitForExpectations(timeout: 1.0)
  }

  func testClientStreamingRetainsClientUntilCallFinished() {
    let callCompletionHandlerExpectation = expectation(description: "call completion handler called")
    var call: Echo_EchoCollectCall? = try! client.collect { result in
      XCTAssertEqual(.ok, result.statusCode)
      callCompletionHandlerExpectation.fulfill()
    }
    let responseCompletionHandlerExpectation = expectation(description: "response completion handler called")
    try! call!.closeAndReceive { response in
      XCTAssertEqual("", response.result?.text)
      responseCompletionHandlerExpectation.fulfill()
    }
    call = nil
    // The call should complete even when the client and call are not retained.
    client = nil

    waitForExpectations(timeout: 1.0)
  }

  func testServerStreamingRetainsClientUntilCallFinished() {
    let callCompletionHandlerExpectation = expectation(description: "call completion handler called")
    _ = try! client.expand(.init()) { result in
      XCTAssertEqual(.ok, result.statusCode)
      callCompletionHandlerExpectation.fulfill()
    }
    // The call should complete even when the client and call are not retained.
    client = nil

    waitForExpectations(timeout: 1.0)
  }

  func testBidiStreamingRetainsClientUntilCallFinished() {
    let callCompletionHandlerExpectation = expectation(description: "call completion handler called")
    var call: Echo_EchoUpdateCall? = try! client.update { result in
      XCTAssertEqual(.ok, result.statusCode)
      callCompletionHandlerExpectation.fulfill()
    }
    let closeSendCompletionHandlerExpectation = expectation(description: "closeSend completion handler called")
    try! call!.closeSend {
      closeSendCompletionHandlerExpectation.fulfill()
    }
    call = nil
    // The call should complete even when the client and call are not retained.
    client = nil

    waitForExpectations(timeout: 1.0)
  }
}
