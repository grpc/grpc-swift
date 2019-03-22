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

final class ChannelShutdownTests: BasicEchoTestCase {
}

extension ChannelShutdownTests {
  func testThrowsWhenCreatingCallWithAlreadyShutDownChannel() {
    self.client.channel.shutdown()

    XCTAssertThrowsError(try self.client.channel.makeCall("foobar")) { error in
      XCTAssertEqual(.alreadyShutdown, error as? Channel.Error)
    }
  }

  func testCallReceiveThrowsWhenChannelIsShutDown() {
    let call = try! self.client.channel.makeCall("foo")
    self.client.channel.shutdown()

    XCTAssertThrowsError(try call.receiveMessage { _ in }) { error in
      XCTAssertEqual(.completionQueueShutdown, error as? CallError)
    }
  }

  func testCallCloseThrowsWhenChannelIsShutDown() {
    let call = try! self.client.channel.makeCall("foo")
    self.client.channel.shutdown()

    XCTAssertThrowsError(try call.close()) { error in
      XCTAssertEqual(.completionQueueShutdown, error as? CallError)
    }
  }

  func testCallCloseAndReceiveThrowsWhenChannelIsShutDown() {
    let call = try! self.client.channel.makeCall("foo")
    self.client.channel.shutdown()

    XCTAssertThrowsError(try call.closeAndReceiveMessage { _ in }) { error in
      XCTAssertEqual(.completionQueueShutdown, error as? CallError)
    }
  }

  func testCallSendThrowsWhenChannelIsShutDown() {
    let call = try! self.client.channel.makeCall("foo")
    self.client.channel.shutdown()

    XCTAssertThrowsError(try call.sendMessage(data: Data())) { error in
      XCTAssertEqual(.completionQueueShutdown, error as? CallError)
    }
  }

  func testCancelsActiveCallWhenShutdownIsCalled() {
    let errorExpectation = self.expectation(description: "error is returned to call when channel is shut down")
    let call = try! self.client.channel.makeCall("foo")

    try! call.receiveMessage { result in
      XCTAssertFalse(result.success)
      errorExpectation.fulfill()
    }

    self.client.channel.shutdown()
    self.waitForExpectations(timeout: 0.1)

    XCTAssertThrowsError(try call.close()) { error in
      XCTAssertEqual(.completionQueueShutdown, error as? CallError)
    }
  }
}
