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
  /// In the 'Handling' state the user handler has been invoked and the request stream is open (but
  /// the request metadata has already been seen). We can transition to a new state either by
  /// receiving the end of the request stream or by closing the response stream. Cancelling also
  /// moves us to the finished state.
  @usableFromInline
  internal struct Handling {
    @usableFromInline
    typealias NextStateAndOutput<Output> = ServerHandlerStateMachine.NextStateAndOutput<
      ServerHandlerStateMachine.Handling.NextState,
      Output
    >

    /// The response headers.
    @usableFromInline
    internal private(set) var responseHeaders: ResponseMetadata
    /// The response trailers.
    @usableFromInline
    internal private(set) var responseTrailers: ResponseMetadata
    /// The request headers.
    @usableFromInline
    internal let requestHeaders: HPACKHeaders

    /// Transition from the 'Idle' state.
    @inlinable
    init(from state: ServerHandlerStateMachine.Idle, requestHeaders: HPACKHeaders) {
      self.responseHeaders = .notWritten([:])
      self.responseTrailers = .notWritten([:])
      self.requestHeaders = requestHeaders
    }

    @inlinable
    mutating func setResponseHeaders(
      _ metadata: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      self.responseHeaders.update(metadata)
      return .init(nextState: .handling(self))
    }

    @inlinable
    mutating func setResponseTrailers(
      _ metadata: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      self.responseTrailers.update(metadata)
      return .init(nextState: .handling(self))
    }

    @inlinable
    mutating func handleMetadata() -> Self.NextStateAndOutput<HandleMetadataAction> {
      // We are in the 'Handling' state because we received metadata. If we receive it again we
      // should cancel the RPC.
      return .init(nextState: .handling(self), output: .cancel)
    }

    @inlinable
    mutating func handleMessage() -> Self.NextStateAndOutput<HandleMessageAction> {
      // We can always forward a message since receiving the end of the request stream causes a
      // transition to the 'draining' state.
      return .init(nextState: .handling(self), output: .forward)
    }

    @inlinable
    mutating func handleEnd() -> Self.NextStateAndOutput<HandleEndAction> {
      // The request stream is finished: move to the draining state so the user handler can finish
      // executing.
      return .init(nextState: .draining(from: self), output: .forward)
    }

    @inlinable
    mutating func sendMessage() -> Self.NextStateAndOutput<SendMessageAction> {
      let headers = self.responseHeaders.getIfNotWritten()
      return .init(nextState: .handling(self), output: .intercept(headers: headers))
    }

    @inlinable
    mutating func sendStatus() -> Self.NextStateAndOutput<SendStatusAction> {
      return .init(
        nextState: .finished(from: self),
        output: .intercept(
          requestHeaders: self.requestHeaders,
          // If trailers had been written we'd already be in the finished state so
          // the force unwrap is okay here.
          trailers: self.responseTrailers.getIfNotWritten()!
        )
      )
    }

    @inlinable
    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      return .init(nextState: .finished(from: self), output: .cancelAndNilOutHandlerComponents)
    }
  }
}
#endif // compiler(>=5.6)
