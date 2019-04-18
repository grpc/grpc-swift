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
@testable import SwiftGRPC
import XCTest

final class ChannelConnectivityTests: BasicEchoTestCase {
  override var defaultTimeout: TimeInterval { return 0.4 }
}

extension ChannelConnectivityTests {
  func testDanglingConnectivityObserversDontCrash() {
    let completionHandlerExpectation = expectation(description: "completion handler called")

    client.channel.addConnectivityObserver { connectivityState in
      print("ConnectivityState: \(connectivityState)")
    }

    let request = Echo_EchoRequest(text: "foo bar baz foo bar baz")
    _ = try! client.expand(request) { callResult in
      print("callResult.statusCode: \(callResult.statusCode)")
      completionHandlerExpectation.fulfill()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
      self.client = nil // Deallocating the client
    }

    waitForExpectations(timeout: 0.5)
  }

  func testMultipleConnectivityObserversAreCalled() {
    // Linux doesn't yet support `assertForOverFulfill` or `expectedFulfillmentCount`, and since these are
    // called multiple times, we can't use expectations. https://bugs.swift.org/browse/SR-6249
    var firstObserverCalled = false
    var secondObserverCalled = false
    client.channel.addConnectivityObserver { _ in firstObserverCalled = true }
    client.channel.addConnectivityObserver { _ in secondObserverCalled = true }

    let completionHandlerExpectation = expectation(description: "completion handler called")
    _ = try! client.get(Echo_EchoRequest(text: "foo")) { _, _ in
      completionHandlerExpectation.fulfill()
    }

    waitForExpectations(timeout: 0.5)
    XCTAssertTrue(firstObserverCalled)
    XCTAssertTrue(secondObserverCalled)
  }
}
