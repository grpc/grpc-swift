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
    let firstBatchReceived = self.expectation(description: "first batch received")
    let counter = ResponseCounter(expectation: firstBatchReceived)

    let update = self.client.update { _ in
      counter.increment()
    }

    // Send the first batch.
    let firstBatch = ["foo", "bar", "baz"].map { Echo_EchoRequest(text: $0) }
    firstBatchReceived.expectedFulfillmentCount = firstBatch.count
    XCTAssertNoThrow(try update.sendMessages(firstBatch).wait())

    // Wait for the first batch of resonses.
    self.wait(for: [firstBatchReceived], timeout: 0.5)

    // Send more messages, but don't flush.
    let secondBatchNotReceived = self.expectation(description: "second batch not received")
    secondBatchNotReceived.isInverted = true
    counter.expectation = secondBatchNotReceived

    let secondBatch = (0..<3).map { Echo_EchoRequest(text: "\($0)") }
    update.sendMessages(secondBatch, promise: nil, flush: false)

    // Wait and check that the expectation hasn't been fulfilled (because we haven't flushed).
    self.wait(for: [secondBatchNotReceived], timeout: 0.5)

    let secondBatchReceived = self.expectation(description: "second batch received")
    secondBatchReceived.expectedFulfillmentCount = secondBatch.count
    counter.expectation = secondBatchReceived

    // Flush the messages: we should get responses now.
    update.flush()
    self.wait(for: [secondBatchReceived], timeout: 0.5)

    // End the call.
    update.sendEnd(promise: nil)

    let statusReceived = self.expectation(description: "status received")
    update.status.map { $0.code }.assertEqual(.ok, fulfill: statusReceived)

    self.wait(for: [statusReceived], timeout: 1.0)
  }

}
