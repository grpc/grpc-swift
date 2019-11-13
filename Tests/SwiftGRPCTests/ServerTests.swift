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
import Dispatch
import Foundation
@testable import SwiftGRPC
import XCTest

class ServerTests: XCTestCase {
  static var allTests: [(String, (ServerTests) -> () throws -> Void)] {
    return [
      ("testDoesNotCrashWhenServerTimesOutWithoutReceivingARequest", testDoesNotCrashWhenServerTimesOutWithoutReceivingARequest)
    ]
  }
}

extension ServerTests {
  func testDoesNotCrashWhenServerTimesOutWithoutReceivingARequest() {
    let server = ServiceServer(address: address, serviceProviders: [EchoProvider()], loopTimeout: 0.01)
    server.start()
    Thread.sleep(forTimeInterval: 0.02)
    let client = Echo_EchoServiceClient(address: address, secure: false)
    client.timeout = 0.1
    XCTAssertEqual("Swift echo get: foo", try client.get(Echo_EchoRequest(text: "foo")).text)
    server.server.stop()
  }
}
