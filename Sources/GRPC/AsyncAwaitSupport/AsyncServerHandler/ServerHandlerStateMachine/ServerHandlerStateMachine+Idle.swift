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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  /// In the 'Idle' state nothing has happened. To advance we must either receive metadata (i.e.
  /// the request headers) and invoke the handler, or we are cancelled.
  @usableFromInline
  internal struct Idle {
    typealias NextStateAndOutput<Output> = ServerHandlerStateMachine.NextStateAndOutput<
      ServerHandlerStateMachine.Idle.NextState,
      Output
    >

    /// A ref to the `UserInfo`. We hold on to this until we're ready to invoke the handler.
    let userInfoRef: Ref<UserInfo>
    /// A bag of bits required to construct a context passed to the user handler when it is invoked.
    let callHandlerContext: CallHandlerContext

    /// The state of the inbound stream, i.e. the request stream.
    internal private(set) var inboundState: ServerInterceptorStateMachine.InboundStreamState

    init(userInfoRef: Ref<UserInfo>, context: CallHandlerContext) {
      self.userInfoRef = userInfoRef
      self.callHandlerContext = context
      self.inboundState = .idle
    }

    mutating func handleMetadata() -> Self.NextStateAndOutput<HandleMetadataAction> {
      let action: HandleMetadataAction

      switch self.inboundState.receiveMetadata() {
      case .accept:
        // We tell the caller to invoke the handler immediately: they should then call
        // 'handlerInvoked' on the state machine which will cause a transition to the next state.
        action = .invokeHandler(self.userInfoRef, self.callHandlerContext)
      case .reject:
        action = .cancel
      }

      return .init(nextState: .idle(self), output: action)
    }

    mutating func handleMessage() -> Self.NextStateAndOutput<HandleMessageAction> {
      // We can't receive a message before the metadata, doing so is a protocol violation.
      return .init(nextState: .idle(self), output: .cancel)
    }

    mutating func handleEnd() -> Self.NextStateAndOutput<HandleEndAction> {
      // Receiving 'end' before we start is odd but okay, just cancel.
      return .init(nextState: .idle(self), output: .cancel)
    }

    mutating func handlerInvoked(
      context: GRPCAsyncServerCallContext
    ) -> Self.NextStateAndOutput<Void> {
      // The handler was invoked as a result of receiving metadata. Move to the next state.
      return .init(nextState: .handling(from: self, context: context))
    }

    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      // There's no handler to cancel. Move straight to finished.
      return .init(nextState: .finished(from: self), output: .none)
    }
  }
}
#endif // compiler(>=5.6)
