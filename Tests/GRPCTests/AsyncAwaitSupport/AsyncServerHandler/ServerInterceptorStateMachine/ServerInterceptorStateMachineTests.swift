/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
#if compiler(>=5.6)
@testable import GRPC
import NIOEmbedded
import XCTest

final class ServerInterceptorStateMachineTests: GRPCTestCase {
  func testInterceptRequestMetadataWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptRequestMetadata().assertCancel() // Can't receive metadata twice.
  }

  func testInterceptRequestMessageWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMessage().assertCancel()
  }

  func testInterceptRequestEndWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestEnd().assertIntercept()
    stateMachine.interceptRequestEnd().assertCancel() // Can't receive end twice.
  }

  func testInterceptedRequestMetadataWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()
    stateMachine.interceptedRequestMetadata().assertCancel() // Can't intercept metadata twice.
  }

  func testInterceptedRequestMessageWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()
    for _ in 0 ..< 100 {
      stateMachine.interceptRequestMessage().assertIntercept()
      stateMachine.interceptedRequestMessage().assertForward()
    }
  }

  func testInterceptedRequestEndWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()
    stateMachine.interceptRequestEnd().assertIntercept()
    stateMachine.interceptedRequestEnd().assertForward()
    stateMachine.interceptedRequestEnd().assertCancel() // Can't intercept end twice.
  }

  func testInterceptResponseMetadataWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptResponseMetadata().assertCancel()
  }

  func testInterceptedResponseMetadataWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptedResponseMetadata().assertForward()
    stateMachine.interceptedResponseMetadata().assertCancel()
  }

  func testInterceptResponseMessageWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptResponseMessage().assertIntercept()
  }

  func testInterceptedResponseMessageWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptedResponseMetadata().assertForward()
    stateMachine.interceptResponseMessage().assertIntercept()
    stateMachine.interceptedResponseMessage().assertForward()
    // Still fine: interceptor could insert extra message.
    stateMachine.interceptedResponseMessage().assertForward()
  }

  func testInterceptResponseStatusWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptResponseMessage().assertIntercept()
    stateMachine.interceptResponseStatus().assertIntercept()

    stateMachine.interceptResponseMessage().assertCancel()
    stateMachine.interceptResponseStatus().assertCancel()
  }

  func testInterceptedResponseStatusWhenIntercepting() {
    var stateMachine = ServerInterceptorStateMachine()
    stateMachine.interceptRequestMetadata().assertIntercept()
    stateMachine.interceptedRequestMetadata().assertForward()

    stateMachine.interceptResponseMetadata().assertIntercept()
    stateMachine.interceptedResponseMetadata().assertForward()
    stateMachine.interceptResponseStatus().assertIntercept()
    stateMachine.interceptedResponseStatus().assertForward()
  }

  func testAllOperationsDropWhenFinished() {
    var stateMachine = ServerInterceptorStateMachine()
    // Get to the finished state.
    stateMachine.cancel().assertNilOutInterceptorPipeline()

    stateMachine.interceptRequestMetadata().assertDrop()
    stateMachine.interceptedRequestMetadata().assertDrop()
    stateMachine.interceptRequestMessage().assertDrop()
    stateMachine.interceptedRequestMessage().assertDrop()
    stateMachine.interceptRequestEnd().assertDrop()
    stateMachine.interceptedRequestEnd().assertDrop()

    stateMachine.interceptResponseMetadata().assertDrop()
    stateMachine.interceptedResponseMetadata().assertDrop()
    stateMachine.interceptResponseMessage().assertDrop()
    stateMachine.interceptedResponseMessage().assertDrop()
    stateMachine.interceptResponseStatus().assertDrop()
    stateMachine.interceptedResponseStatus().assertDrop()
  }
}

extension ServerInterceptorStateMachine.InterceptAction {
  func assertIntercept() {
    XCTAssertEqual(self, .intercept)
  }

  func assertCancel() {
    XCTAssertEqual(self, .cancel)
  }

  func assertDrop() {
    XCTAssertEqual(self, .drop)
  }
}

extension ServerInterceptorStateMachine.InterceptedAction {
  func assertForward() {
    XCTAssertEqual(self, .forward)
  }

  func assertCancel() {
    XCTAssertEqual(self, .cancel)
  }

  func assertDrop() {
    XCTAssertEqual(self, .drop)
  }
}

extension ServerInterceptorStateMachine.CancelAction {
  func assertNilOutInterceptorPipeline() {
    XCTAssertEqual(self, .nilOutInterceptorPipeline)
  }
}

#endif // compiler(>=5.6)
