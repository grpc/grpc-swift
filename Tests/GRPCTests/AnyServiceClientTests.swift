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
import EchoModel
import XCTest

class AnyServiceClientTests: EchoTestCaseBase {

  var anyServiceClient: AnyServiceClient {
    return AnyServiceClient(connection: self.client.connection)
  }

  func testUnary() throws {
    let get = self.anyServiceClient.makeUnaryCall(
      path: "/echo.Echo/Get",
      request: Echo_EchoRequest.with { $0.text = "foo" },
      responseType: Echo_EchoResponse.self)

    XCTAssertEqual(try get.status.map { $0.code }.wait(), .ok)
  }

  func testClientStreaming() throws {
    let collect = self.anyServiceClient.makeClientStreamingCall(
      path: "/echo.Echo/Collect",
      requestType: Echo_EchoRequest.self,
      responseType: Echo_EchoResponse.self)

    collect.sendEnd(promise: nil)

    XCTAssertEqual(try collect.status.map { $0.code }.wait(), .ok)
  }

  func testServerStreaming() throws {
    let expand = self.anyServiceClient.makeServerStreamingCall(
      path: "/echo.Echo/Expand",
      request: Echo_EchoRequest.with { $0.text = "foo" },
      responseType: Echo_EchoResponse.self,
      handler: { _ in })

    XCTAssertEqual(try expand.status.map { $0.code }.wait(), .ok)
  }

  func testBidirectionalStreaming() throws {
    let update = self.anyServiceClient.makeBidirectionalStreamingCall(
      path: "/echo.Echo/Update",
      requestType: Echo_EchoRequest.self,
      responseType: Echo_EchoResponse.self,
      handler: { _ in })

    update.sendEnd(promise: nil)

    XCTAssertEqual(try update.status.map { $0.code }.wait(), .ok)
  }
}
