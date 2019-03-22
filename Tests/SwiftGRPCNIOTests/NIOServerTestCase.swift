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

extension Echo_EchoRequest {
  init(text: String) {
    self.text = text
  }
}

extension Echo_EchoResponse {
  init(text: String) {
    self.text = text
  }
}

class NIOServerTestCase: XCTestCase {
  func makeProvider() -> Echo_EchoProvider { return EchoProvider() }

  var provider: Echo_EchoProvider!
  var client: Echo_EchoServiceClient!

  var defaultTimeout: TimeInterval { return 1.0 }
  var address: String { return "localhost:5050" }

  override func setUp() {
    super.setUp()

    provider = makeProvider()

    client = Echo_EchoServiceClient(address: address, secure: false)

    client.timeout = defaultTimeout
  }

  override func tearDown() {
    client = nil

    super.tearDown()
  }
}
