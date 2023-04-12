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
extension ServerInterceptorStateMachine {
  /// The 'Intercepting' state is responsible for validating that appropriate message parts are
  /// forwarded to the interceptor pipeline and that messages parts which have been emitted from the
  /// interceptors are valid to forward to either the network or the user handler (as interceptors
  /// may emit new message parts).
  ///
  /// We only transition to the next state on `cancel` (which happens at the end of every RPC).
  @usableFromInline
  struct Intercepting {
    @usableFromInline
    typealias NextStateAndOutput<Output> =
      ServerInterceptorStateMachine.NextStateAndOutput<Self.NextState, Output>

    /// From the network into the interceptors.
    @usableFromInline
    internal private(set) var requestStreamIn: InboundStreamState
    /// From the interceptors out to the handler.
    @usableFromInline
    internal private(set) var requestStreamOut: InboundStreamState

    /// From the handler into the interceptors.
    @usableFromInline
    internal private(set) var responseStreamIn: OutboundStreamState
    /// From the interceptors out to the network.
    @usableFromInline
    internal private(set) var responseStreamOut: OutboundStreamState

    @usableFromInline
    init() {
      self.requestStreamIn = .idle
      self.requestStreamOut = .idle
      self.responseStreamIn = .idle
      self.responseStreamOut = .idle
    }

    @inlinable
    mutating func interceptRequestMetadata() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.requestStreamIn.receiveMetadata()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptRequestMessage() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.requestStreamIn.receiveMessage()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptRequestEnd() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.requestStreamIn.receiveEnd()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedRequestMetadata() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.requestStreamOut.receiveMetadata()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedRequestMessage() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.requestStreamOut.receiveMessage()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedRequestEnd() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.requestStreamOut.receiveEnd()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptResponseMetadata() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.responseStreamIn.sendMetadata()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptResponseMessage() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.responseStreamIn.sendMessage()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptResponseStatus() -> Self.NextStateAndOutput<InterceptAction> {
      let filter = self.responseStreamIn.sendEnd()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedResponseMetadata() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.responseStreamOut.sendMetadata()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedResponseMessage() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.responseStreamOut.sendMessage()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func interceptedResponseStatus() -> Self.NextStateAndOutput<InterceptedAction> {
      let filter = self.responseStreamOut.sendEnd()
      return .init(nextState: .intercepting(self), output: .init(from: filter))
    }

    @inlinable
    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      let output: CancelAction

      // Check the state of the response stream. If we haven't sent a status then we should emit
      // one first. It may not reach the other side but we should try.
      switch self.responseStreamOut {
      case .idle, .writingMessages:
        output = .sendStatusThenNilOutInterceptorPipeline
      case .done:
        output = .nilOutInterceptorPipeline
      }

      return .init(nextState: .finished(from: self), output: output)
    }
  }
}
