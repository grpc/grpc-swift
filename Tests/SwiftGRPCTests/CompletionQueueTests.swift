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

fileprivate class ClosingProvider: Echo_EchoProvider {
  var doneExpectation: XCTestExpectation!

  func get(request: Echo_EchoRequest, session: Echo_EchoGetSession) throws -> Echo_EchoResponse {
    return Echo_EchoResponse()
  }

  func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws -> ServerStatus? {
    let closeSem = DispatchSemaphore(value: 0)
    try! session.close(withStatus: .ok) {
      closeSem.signal()
    }
    XCTAssertThrowsError(try session.send(Echo_EchoResponse()))
    doneExpectation.fulfill()
    return nil
  }

  func collect(session: Echo_EchoCollectSession) throws -> Echo_EchoResponse? { fatalError("not implemented") }

  func update(session: Echo_EchoUpdateSession) throws -> ServerStatus? { fatalError("not implemented") }
}

class CompletionQueueTests: BasicEchoTestCase {
  override func makeProvider() -> Echo_EchoProvider { return ClosingProvider() }
}

extension CompletionQueueTests {
  func testCompletionQueueThrowsAfterShutdown() {
    (self.provider as! ClosingProvider).doneExpectation = expectation(description: "end of server-side request handler reached")

    let completionHandlerExpectation = expectation(description: "completion handler called")
    _ = try! client.expand(Echo_EchoRequest(text: "foo bar baz")) { callResult in
      XCTAssertEqual(.ok, callResult.statusCode)
      XCTAssertEqual("OK", callResult.statusMessage)
      completionHandlerExpectation.fulfill()
    }

    waitForExpectations(timeout: defaultTimeout)
  }
}
