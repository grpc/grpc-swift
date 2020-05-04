/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import GRPC
import NIO
import XCTest

class EchoTestClientExampleTests: GRPCTestCase {
  func testUnary() {
    let client = Echo_EchoTestClient()
    let loop = EmbeddedEventLoop()

    let getResponseStream = client.makeGetTestResponse(on: loop)
    getResponseStream.sendResponse(.with {
      $0.text = "This response doesn't depend on the request."
    })

    // We should probably (?) just `sendEnd()` anyway after `sendResponse()` is called on unary
    // response streams.
    getResponseStream.sendEnd()

    let get = client.get(.with {
      $0.text = "This request will be ignored"
    })

    XCTAssertEqual(try get.response.wait(), .with {
      $0.text = "This response doesn't depend on the request."
    })
    XCTAssertEqual(try get.status.wait(), GRPCStatus.ok)
  }

  func testBidirectional() {
    let client = Echo_EchoTestClient()
    let loop = EmbeddedEventLoop()

    let responseStream = client.makeUpdateTestResponse(on: loop)

    // We can send responses before making the call...
    responseStream.sendResponse(.with { $0.text = "1" })

    var responses: [Echo_EchoResponse] = []
    let update = client.update {
      responses.append($0)
    }

    // ... as well as after making the call.
    responseStream.sendResponse(.with { $0.text = "2" })
    XCTAssertEqual(responses, [.with { $0.text = "1" }, .with { $0.text = "2" }])

    // We still have to complete the call though:
    responseStream.sendEnd(status: GRPCStatus(code: .dataLoss, message: nil))
    XCTAssertEqual(try update.status.wait(), GRPCStatus(code: .dataLoss, message: nil))

    // And messages sent after the status will be ignored.
    responseStream.sendResponse(.with { $0.text = "Ignore me; I came after the status." })
    XCTAssertEqual(responses, [.with { $0.text = "1" }, .with { $0.text = "2" }])
  }

}
