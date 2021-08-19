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
import NIOCore
import XCTest

class FakeChannelTests: GRPCTestCase {
  typealias Request = Echo_EchoRequest
  typealias Response = Echo_EchoResponse

  var channel: FakeChannel!

  override func setUp() {
    super.setUp()
    self.channel = FakeChannel(logger: self.clientLogger)
  }

  private func makeUnaryResponse(
    path: String = "/foo/bar",
    requestHandler: @escaping (FakeRequestPart<Request>) -> Void = { _ in }
  ) -> FakeUnaryResponse<Request, Response> {
    return self.channel.makeFakeUnaryResponse(path: path, requestHandler: requestHandler)
  }

  private func makeStreamingResponse(
    path: String = "/foo/bar",
    requestHandler: @escaping (FakeRequestPart<Request>) -> Void = { _ in }
  ) -> FakeStreamingResponse<Request, Response> {
    return self.channel.makeFakeStreamingResponse(path: path, requestHandler: requestHandler)
  }

  private func makeUnaryCall(
    request: Request,
    path: String = "/foo/bar",
    callOptions: CallOptions = CallOptions()
  ) -> UnaryCall<Request, Response> {
    return self.channel.makeUnaryCall(path: path, request: request, callOptions: callOptions)
  }

  private func makeBidirectionalStreamingCall(
    path: String = "/foo/bar",
    callOptions: CallOptions = CallOptions(),
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    return self.channel.makeBidirectionalStreamingCall(
      path: path,
      callOptions: callOptions,
      handler: handler
    )
  }

  func testUnary() {
    let response = self.makeUnaryResponse { part in
      switch part {
      case let .message(request):
        XCTAssertEqual(request, Request.with { $0.text = "Foo" })
      default:
        ()
      }
    }

    let call = self.makeUnaryCall(request: .with { $0.text = "Foo" })

    XCTAssertNoThrow(try response.sendMessage(.with { $0.text = "Bar" }))
    XCTAssertEqual(try call.response.wait(), .with { $0.text = "Bar" })
    XCTAssertTrue(try call.status.map { $0.isOk }.wait())
  }

  func testBidirectional() {
    var requests: [Request] = []
    let response = self.makeStreamingResponse { part in
      switch part {
      case let .message(request):
        requests.append(request)
      default:
        ()
      }
    }

    var responses: [Response] = []
    let call = self.makeBidirectionalStreamingCall {
      responses.append($0)
    }

    XCTAssertNoThrow(try call.sendMessage(.with { $0.text = "1" }).wait())
    XCTAssertNoThrow(try call.sendMessage(.with { $0.text = "2" }).wait())
    XCTAssertNoThrow(try call.sendMessage(.with { $0.text = "3" }).wait())
    XCTAssertNoThrow(try call.sendEnd().wait())

    XCTAssertEqual(requests, (1 ... 3).map { number in .with { $0.text = "\(number)" } })

    XCTAssertNoThrow(try response.sendMessage(.with { $0.text = "4" }))
    XCTAssertNoThrow(try response.sendMessage(.with { $0.text = "5" }))
    XCTAssertNoThrow(try response.sendMessage(.with { $0.text = "6" }))
    XCTAssertNoThrow(try response.sendEnd())

    XCTAssertEqual(responses, (4 ... 6).map { number in .with { $0.text = "\(number)" } })
    XCTAssertTrue(try call.status.map { $0.isOk }.wait())
  }

  func testMissingResponse() {
    let call = self.makeUnaryCall(request: .with { $0.text = "Not going to work" })

    XCTAssertThrowsError(try call.initialMetadata.wait())
    XCTAssertThrowsError(try call.response.wait())
    XCTAssertThrowsError(try call.trailingMetadata.wait())
    XCTAssertFalse(try call.status.map { $0.isOk }.wait())
  }

  func testResponseIsReallyDequeued() {
    let response = self.makeUnaryResponse()
    let call = self.makeUnaryCall(request: .with { $0.text = "Ping" })

    XCTAssertNoThrow(try response.sendMessage(.with { $0.text = "Pong" }))
    XCTAssertEqual(try call.response.wait(), .with { $0.text = "Pong" })

    let failedCall = self.makeUnaryCall(request: .with { $0.text = "Not going to work" })
    XCTAssertThrowsError(try failedCall.initialMetadata.wait())
    XCTAssertThrowsError(try failedCall.response.wait())
    XCTAssertThrowsError(try failedCall.trailingMetadata.wait())
    XCTAssertFalse(try failedCall.status.map { $0.isOk }.wait())
  }

  func testHasResponseStreamsEnqueued() {
    XCTAssertFalse(self.channel.hasFakeResponseEnqueued(forPath: "whatever"))
    _ = self.makeUnaryResponse(path: "whatever")
    XCTAssertTrue(self.channel.hasFakeResponseEnqueued(forPath: "whatever"))
    _ = self.makeUnaryCall(request: .init(), path: "whatever")
    XCTAssertFalse(self.channel.hasFakeResponseEnqueued(forPath: "whatever"))
  }
}
