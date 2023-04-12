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
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  @usableFromInline
  internal struct Finished {
    @usableFromInline
    typealias NextStateAndOutput<Output> = ServerHandlerStateMachine.NextStateAndOutput<
      ServerHandlerStateMachine.Finished.NextState,
      Output
    >

    @inlinable
    internal init(from state: ServerHandlerStateMachine.Idle) {}
    @inlinable
    internal init(from state: ServerHandlerStateMachine.Handling) {}
    @inlinable
    internal init(from state: ServerHandlerStateMachine.Draining) {}

    @inlinable
    mutating func setResponseHeaders(
      _ headers: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      return .init(nextState: .finished(self))
    }

    @inlinable
    mutating func setResponseTrailers(
      _ metadata: HPACKHeaders
    ) -> Self.NextStateAndOutput<Void> {
      return .init(nextState: .finished(self))
    }

    @inlinable
    mutating func handleMetadata() -> Self.NextStateAndOutput<HandleMetadataAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    @inlinable
    mutating func handleMessage() -> Self.NextStateAndOutput<HandleMessageAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    @inlinable
    mutating func handleEnd() -> Self.NextStateAndOutput<HandleEndAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    @inlinable
    mutating func sendMessage() -> Self.NextStateAndOutput<SendMessageAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func sendStatus() -> Self.NextStateAndOutput<SendStatusAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      return .init(nextState: .finished(self), output: .cancelAndNilOutHandlerComponents)
    }
  }
}
