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

class ClientCancellingTests: EchoTestCaseBase {
  func testUnary() {
    let statusReceived = self.expectation(description: "status received")
    let responseReceived = self.expectation(description: "response received")

    let call = client.get(Echo_EchoRequest(text: "foo bar baz"))
    call.cancel()

    call.response.whenFailure { error in
      XCTAssertEqual((error as? GRPCStatus)?.code, .cancelled)
      responseReceived.fulfill()
    }

    call.status.whenSuccess { status in
      XCTAssertEqual(status.code, .cancelled)
      statusReceived.fulfill()
    }

    waitForExpectations(timeout: self.defaultTestTimeout)
  }

  func testClientStreaming() throws {
    let statusReceived = self.expectation(description: "status received")
    let responseReceived = self.expectation(description: "response received")

    let call = client.collect()
    call.cancel()

    call.response.whenFailure { error in
      XCTAssertEqual((error as? GRPCStatus)?.code, .cancelled)
      responseReceived.fulfill()
    }

    call.status.whenSuccess { status in
      XCTAssertEqual(status.code, .cancelled)
      statusReceived.fulfill()
    }

    waitForExpectations(timeout: self.defaultTestTimeout)
  }

  func testServerStreaming() {
    let statusReceived = self.expectation(description: "status received")

    let call = client.expand(Echo_EchoRequest(text: "foo bar baz")) { response in
      XCTFail("response should not be received after cancelling call")
    }
    call.cancel()

    call.status.whenSuccess { status in
      XCTAssertEqual(status.code, .cancelled)
      statusReceived.fulfill()
    }

    waitForExpectations(timeout: self.defaultTestTimeout)
  }

  func testBidirectionalStreaming() {
    let statusReceived = self.expectation(description: "status received")

    let call = client.update { response in
      XCTFail("response should not be received after cancelling call")
    }
    call.cancel()

    call.status.whenSuccess { status in
      XCTAssertEqual(status.code, .cancelled)
      statusReceived.fulfill()
    }

    waitForExpectations(timeout: self.defaultTestTimeout)
  }
}
