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
import EchoModel
import Foundation
import GRPC
import XCTest

class StreamingRequestClientCallTests: EchoTestCaseBase {
  class ResponseCounter {
    var expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
      self.expectation = expectation
    }

    func increment() {
      self.expectation.fulfill()
    }
  }

  func testSendMessages() throws {
    let messagesReceived = self.expectation(description: "messages received")
    let counter = ResponseCounter(expectation: messagesReceived)

    let update = self.client.update { _ in
      counter.increment()
    }

    // Send the first batch.
    let requests = ["foo", "bar", "baz"].map { Echo_EchoRequest(text: $0) }
    messagesReceived.expectedFulfillmentCount = requests.count
    XCTAssertNoThrow(try update.sendMessages(requests).wait())

    // Wait for the responses.
    self.wait(for: [messagesReceived], timeout: 0.5)

    let statusReceived = self.expectation(description: "status received")
    update.status.map { $0.code }.assertEqual(.ok, fulfill: statusReceived)

    // End the call.
    update.sendEnd(promise: nil)

    self.wait(for: [statusReceived], timeout: 0.5)
  }
}
