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

class ClientCancellingTests: EchoTestCaseBase {
  func testUnary() throws {
    let call = client.get(Echo_EchoRequest(text: "foo bar baz"))
    call.cancel(promise: nil)

    XCTAssertThrowsError(try call.response.wait()) { error in
      XCTAssertEqual((error as? GRPCStatus)?.code, .cancelled)
    }

    let status = try call.status.wait()
    XCTAssertEqual(status.code, .cancelled)
  }

  func testClientStreaming() throws {
    let call = client.collect()
    call.cancel(promise: nil)

    XCTAssertThrowsError(try call.response.wait()) { error in
      XCTAssertEqual((error as? GRPCStatus)?.code, .cancelled)
    }

    let status = try call.status.wait()
    XCTAssertEqual(status.code, .cancelled)
  }

  func testServerStreaming() throws {
    let call = client.expand(Echo_EchoRequest(text: "foo bar baz")) { _ in
      XCTFail("response should not be received after cancelling call")
    }
    call.cancel(promise: nil)

    let status = try call.status.wait()
    XCTAssertEqual(status.code, .cancelled)
  }

  func testBidirectionalStreaming() throws {
    let call = client.update { _ in
      XCTFail("response should not be received after cancelling call")
    }
    call.cancel(promise: nil)

    let status = try call.status.wait()
    XCTAssertEqual(status.code, .cancelled)
  }
}
