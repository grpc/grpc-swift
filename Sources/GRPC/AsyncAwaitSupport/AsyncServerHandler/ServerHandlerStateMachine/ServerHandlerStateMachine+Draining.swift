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

    /// The response headers.
    @usableFromInline
    internal private(set) var responseHeaders: ResponseMetadata
    /// The response trailers.
    @usableFromInline
    internal private(set) var responseTrailers: ResponseMetadata
    /// The request headers.
    @usableFromInline
    internal let requestHeaders: HPACKHeaders

    @inlinable
    init(from state: ServerHandlerStateMachine.Handling) {
      self.responseHeaders = state.responseHeaders
      self.responseTrailers = state.responseTrailers
      self.requestHeaders = state.requestHeaders
    }

    @inlinable
    mutating func setResponseHeaders(
      _ metadata: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      self.responseHeaders.update(metadata)
      return .init(nextState: .draining(self))
    }

    @inlinable
    mutating func setResponseTrailers(
      _ metadata: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      self.responseTrailers.update(metadata)
      return .init(nextState: .draining(self))
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
      let headers = self.responseHeaders.getIfNotWritten()
      return .init(nextState: .draining(self), output: .intercept(headers: headers))
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
