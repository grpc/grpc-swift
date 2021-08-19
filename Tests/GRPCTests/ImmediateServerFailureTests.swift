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
import NIOCore
import XCTest

class ImmediatelyFailingEchoProvider: Echo_EchoProvider {
  let interceptors: Echo_EchoServerInterceptorFactoryProtocol? = nil

  static let status: GRPCStatus = .init(code: .unavailable, message: nil)

  func get(
    request: Echo_EchoRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Echo_EchoResponse> {
    return context.eventLoop.makeFailedFuture(ImmediatelyFailingEchoProvider.status)
  }

  func expand(
    request: Echo_EchoRequest,
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    return context.eventLoop.makeFailedFuture(ImmediatelyFailingEchoProvider.status)
  }

  func collect(
    context: UnaryResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.responsePromise.fail(ImmediatelyFailingEchoProvider.status)
    return context.eventLoop.makeSucceededFuture({ _ in
      // no-op
    })
  }

  func update(
    context: StreamingResponseCallContext<Echo_EchoResponse>
  ) -> EventLoopFuture<(StreamEvent<Echo_EchoRequest>) -> Void> {
    context.statusPromise.fail(ImmediatelyFailingEchoProvider.status)
    return context.eventLoop.makeSucceededFuture({ _ in
      // no-op
    })
  }
}

class ImmediatelyFailingProviderTests: EchoTestCaseBase {
  override func makeEchoProvider() -> Echo_EchoProvider {
    return ImmediatelyFailingEchoProvider()
  }

  func testUnary() throws {
    let expcectation = self.makeStatusExpectation()
    let call = self.client.get(Echo_EchoRequest(text: "foo"))
    call.status.map { $0.code }.assertEqual(.unavailable, fulfill: expcectation)

    self.wait(for: [expcectation], timeout: self.defaultTestTimeout)
  }

  func testServerStreaming() throws {
    let expcectation = self.makeStatusExpectation()
    let call = self.client.expand(Echo_EchoRequest(text: "foo")) { response in
      XCTFail("unexpected response: \(response)")
    }

    call.status.map { $0.code }.assertEqual(.unavailable, fulfill: expcectation)
    self.wait(for: [expcectation], timeout: self.defaultTestTimeout)
  }

  func testClientStreaming() throws {
    let expcectation = self.makeStatusExpectation()
    let call = self.client.collect()

    call.status.map { $0.code }.assertEqual(.unavailable, fulfill: expcectation)
    self.wait(for: [expcectation], timeout: self.defaultTestTimeout)
  }

  func testBidirectionalStreaming() throws {
    let expcectation = self.makeStatusExpectation()
    let call = self.client.update { response in
      XCTFail("unexpected response: \(response)")
    }

    call.status.map { $0.code }.assertEqual(.unavailable, fulfill: expcectation)
    self.wait(for: [expcectation], timeout: self.defaultTestTimeout)
  }
}
