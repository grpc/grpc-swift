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
import Foundation
@testable import SwiftGRPC
import XCTest

class ServiceClientTests: BasicEchoTestCase {
  private var sharedChannel: Channel?

  override func setUp() {
    super.setUp()
    sharedChannel = Channel(address: address, secure: false)
  }
  
  override func tearDown() {
    sharedChannel = nil
    super.tearDown()
  }

  func testSharingChannelBetweenClientsUnaryAsync() {
    let firstCallExpectation = expectation(description: "First call completes successfully")
    let secondCallExpectation = expectation(description: "Second call completes successfully")

    do {
      let client1 = Echo_EchoServiceClient(channel: sharedChannel!)
      try _ = client1.get(Echo_EchoRequest(text: "foo")) { _, callResult in
        XCTAssertEqual(.ok, callResult.statusCode)
        firstCallExpectation.fulfill()
      }

      let client2 = Echo_EchoServiceClient(channel: sharedChannel!)
      try _ = client2.get(Echo_EchoRequest(text: "foo")) { _, callResult in
        XCTAssertEqual(.ok, callResult.statusCode)
        secondCallExpectation.fulfill()
      }
    } catch let error {
      XCTFail(error.localizedDescription)
    }

    waitForExpectations(timeout: defaultTimeout)
  }

  func testSharedChannelStillWorksAfterFirstUnaryClientCompletes() {
    do {
      let client1 = Echo_EchoServiceClient(channel: sharedChannel!)
      let response1 = try client1.get(Echo_EchoRequest(text: "foo")).text
      XCTAssertEqual("Swift echo get: foo", response1)
    } catch let error {
      XCTFail(error.localizedDescription)
    }

    do {
      let client2 = Echo_EchoServiceClient(channel: sharedChannel!)
      let response2 = try client2.get(Echo_EchoRequest(text: "foo")).text
      XCTAssertEqual("Swift echo get: foo", response2)
    } catch let error {
      XCTFail(error.localizedDescription)
    }
  }
}
