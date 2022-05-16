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
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  /// In the 'Draining' state the user handler has been invoked and the request stream has been
  /// closed (i.e. we have seen 'end' but it has not necessarily been consumed by the user handler).
  /// We can transition to a new state either by sending the end of the response stream or by
  /// cancelling.
  @usableFromInline
  internal struct Draining {
    @usableFromInline
    typealias NextStateAndOutput<Output> =
      ServerHandlerStateMachine.NextStateAndOutput<
        ServerHandlerStateMachine.Draining.NextState,
        Output
      >

    /// Whether the response headers have been written yet.
    @usableFromInline
    internal private(set) var headersWritten: Bool
    @usableFromInline
    internal let context: GRPCAsyncServerCallContext

    @inlinable
    init(from state: ServerHandlerStateMachine.Handling) {
      self.headersWritten = state.headersWritten
      self.context = state.context
    }

    @inlinable
    mutating func handleMetadata() -> Self.NextStateAndOutput<HandleMetadataAction> {
      // We're already draining, i.e. the inbound stream is closed, cancel the RPC.
      return .init(nextState: .draining(self), output: .cancel)
    }

    @inlinable
    mutating func handleMessage() -> Self.NextStateAndOutput<HandleMessageAction> {
      // We're already draining, i.e. the inbound stream is closed, cancel the RPC.
      return .init(nextState: .draining(self), output: .cancel)
    }

    @inlinable
    mutating func handleEnd() -> Self.NextStateAndOutput<HandleEndAction> {
      // We're already draining, i.e. the inbound stream is closed, cancel the RPC.
      return .init(nextState: .draining(self), output: .cancel)
    }

    @inlinable
    mutating func sendMessage() -> Self.NextStateAndOutput<SendMessageAction> {
      let headers: HPACKHeaders?

      if self.headersWritten {
        headers = nil
      } else {
        self.headersWritten = true
        headers = self.context.initialResponseMetadata
      }

      return .init(nextState: .draining(self), output: .intercept(headers: headers))
    }

    @inlinable
    mutating func sendStatus() -> Self.NextStateAndOutput<SendStatusAction> {
      let trailers = self.context.trailingResponseMetadata
      return .init(
        nextState: .finished(from: self),
        output: .intercept(requestHeaders: self.context.requestMetadata, trailers: trailers)
      )
    }

    @inlinable
    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      return .init(nextState: .finished(from: self), output: .cancelAndNilOutHandlerComponents)
    }
  }
}
#endif // compiler(>=5.6)
