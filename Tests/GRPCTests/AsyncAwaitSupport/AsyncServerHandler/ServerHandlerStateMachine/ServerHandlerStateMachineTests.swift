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
import NIOCore
import NIOEmbedded
import NIOHPACK
import XCTest

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class ServerHandlerStateMachineTests: GRPCTestCase {
  private enum InitialState {
    case idle
    case handling
    case draining
    case finished
  }

  private func makeStateMachine(inState state: InitialState = .idle) -> ServerHandlerStateMachine {
    var stateMachine = ServerHandlerStateMachine(
      userInfoRef: Ref(UserInfo()),
      context: self.makeCallHandlerContext()
    )

    switch state {
    case .idle:
      return stateMachine
    case .handling:
      stateMachine.handleMetadata().assertInvokeHandler()
      stateMachine.handlerInvoked(context: self.makeAsyncServerContext())
      return stateMachine
    case .draining:
      stateMachine.handleMetadata().assertInvokeHandler()
      stateMachine.handlerInvoked(context: self.makeAsyncServerContext())
      stateMachine.handleEnd().assertForward()
      return stateMachine
    case .finished:
      stateMachine.cancel().assertNone()
      return stateMachine
    }
  }

  private func makeCallHandlerContext() -> CallHandlerContext {
    let loop = EmbeddedEventLoop()
    defer {
      try! loop.syncShutdownGracefully()
    }
    return CallHandlerContext(
      logger: self.logger,
      encoding: .disabled,
      eventLoop: loop,
      path: "",
      responseWriter: NoOpResponseWriter(),
      allocator: ByteBufferAllocator(),
      closeFuture: loop.makeSucceededVoidFuture()
    )
  }

  private func makeAsyncServerContext() -> GRPCAsyncServerCallContext {
    return GRPCAsyncServerCallContext(
      headers: [:],
      logger: self.logger,
      userInfoRef: Ref(UserInfo())
    )
  }

  // MARK: - Test Cases

  func testHandleMetadataWhenIdle() {
    var stateMachine = self.makeStateMachine()
    // Receiving metadata is the signal to invoke the user handler.
    stateMachine.handleMetadata().assertInvokeHandler()
    // On invoking the handler we move to the next state. No output.
    stateMachine.handlerInvoked(context: self.makeAsyncServerContext())
  }

  func testHandleMetadataWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // Must not receive metadata more than once.
    stateMachine.handleMetadata().assertInvokeCancel()
  }

  func testHandleMetadataWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // We can't receive metadata more than once.
    stateMachine.handleMetadata().assertInvokeCancel()
  }

  func testHandleMetadataWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    // We can't receive anything when finished.
    stateMachine.handleMetadata().assertInvokeCancel()
  }

  func testHandleMessageWhenIdle() {
    var stateMachine = self.makeStateMachine()
    // Metadata must be received first.
    stateMachine.handleMessage().assertCancel()
  }

  func testHandleMessageWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // Messages are good, we can forward those while handling.
    for _ in 0 ..< 10 {
      stateMachine.handleMessage().assertForward()
    }
  }

  func testHandleMessageWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // We entered the 'draining' state as we received 'end', another message is a protocol
    // violation so cancel.
    stateMachine.handleMessage().assertCancel()
  }

  func testHandleMessageWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    // We can't receive anything when finished.
    stateMachine.handleMessage().assertCancel()
  }

  func testHandleEndWhenIdle() {
    var stateMachine = self.makeStateMachine()
    // Metadata must be received first.
    stateMachine.handleEnd().assertCancel()
  }

  func testHandleEndWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // End is good; it transitions us to the draining state.
    stateMachine.handleEnd().assertForward()
  }

  func testHandleEndWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // We entered the 'draining' state as we received 'end', another 'end' is a protocol
    // violation so cancel.
    stateMachine.handleEnd().assertCancel()
  }

  func testHandleEndWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    // We can't receive anything when finished.
    stateMachine.handleEnd().assertCancel()
  }

  func testSendMessageWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // The first message should prompt headers to be sent as well.
    stateMachine.sendMessage().assertInterceptHeadersThenMessage()
    // Additional messages should be just the message.
    stateMachine.sendMessage().assertInterceptMessage()
  }

  func testSendMessageWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // The first message should prompt headers to be sent as well.
    stateMachine.sendMessage().assertInterceptHeadersThenMessage()
    // Additional messages should be just the message.
    stateMachine.sendMessage().assertInterceptMessage()
  }

  func testSendMessageWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    // We can't send anything if we're finished.
    stateMachine.sendMessage().assertDrop()
  }

  func testSendStatusWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // This moves the state machine to the 'finished' state.
    stateMachine.sendStatus().assertIntercept()
  }

  func testSendStatusWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // This moves the state machine to the 'finished' state.
    stateMachine.sendStatus().assertIntercept()
  }

  func testSendStatusWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    // We can't send anything if we're finished.
    stateMachine.sendStatus().assertDrop()
  }

  func testCancelWhenIdle() {
    var stateMachine = self.makeStateMachine()
    // Cancelling when idle is effectively a no-op; there's nothing to cancel.
    stateMachine.cancel().assertNone()
  }

  func testCancelWhenHandling() {
    var stateMachine = self.makeStateMachine(inState: .handling)
    // We have things to cancel in this state.
    stateMachine.cancel().assertDoCancel()
  }

  func testCancelWhenDraining() {
    var stateMachine = self.makeStateMachine(inState: .draining)
    // We have things to cancel in this state.
    stateMachine.cancel().assertDoCancel()
  }

  func testCancelWhenFinished() {
    var stateMachine = self.makeStateMachine(inState: .finished)
    stateMachine.cancel().assertDoCancel()
  }
}

// MARK: - Action Assertions

extension ServerHandlerStateMachine.HandleMetadataAction {
  func assertInvokeHandler() {
    switch self {
    case .invokeHandler:
      ()
    case .cancel:
      XCTFail("Expected 'invokeHandler' but got \(self)")
    }
  }

  func assertInvokeCancel() {
    switch self {
    case .cancel:
      ()
    case .invokeHandler:
      XCTFail("Expected 'cancel' but got \(self)")
    }
  }
}

extension ServerHandlerStateMachine.HandleMessageAction {
  func assertForward() {
    XCTAssertEqual(self, .forward)
  }

  func assertCancel() {
    XCTAssertEqual(self, .cancel)
  }
}

extension ServerHandlerStateMachine.SendMessageAction {
  func assertInterceptHeadersThenMessage() {
    XCTAssertEqual(self, .intercept(headers: [:]))
  }

  func assertInterceptMessage() {
    XCTAssertEqual(self, .intercept(headers: nil))
  }

  func assertDrop() {
    XCTAssertEqual(self, .drop)
  }
}

extension ServerHandlerStateMachine.SendStatusAction {
  func assertIntercept() {
    XCTAssertEqual(self, .intercept(trailers: [:]))
  }

  func assertDrop() {
    XCTAssertEqual(self, .drop)
  }
}

extension ServerHandlerStateMachine.CancelAction {
  func assertNone() {
    XCTAssertEqual(self, .none)
  }

  func assertDoCancel() {
    XCTAssertEqual(self, .cancelAndNilOutHandlerComponents)
  }
}
#endif // compiler(>=5.6)
