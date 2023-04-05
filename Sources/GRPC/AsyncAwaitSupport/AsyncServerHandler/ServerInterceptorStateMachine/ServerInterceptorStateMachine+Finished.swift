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
  /// The 'Finished' state is, as the name suggests, a terminal state. Nothing can happen in this
  /// state.
  @usableFromInline
  struct Finished {
    @usableFromInline
    typealias NextStateAndOutput<Output> =
      ServerInterceptorStateMachine.NextStateAndOutput<Self.NextState, Output>

    init(from state: ServerInterceptorStateMachine.Intercepting) {}

    @inlinable
    mutating func interceptRequestMetadata() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptRequestMessage() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptRequestEnd() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedRequestMetadata() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedRequestMessage() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedRequestEnd() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptResponseMetadata() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptResponseMessage() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptResponseStatus() -> Self.NextStateAndOutput<InterceptAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedResponseMetadata() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedResponseMessage() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func interceptedResponseStatus() -> Self.NextStateAndOutput<InterceptedAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    @inlinable
    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      return .init(nextState: .finished(self), output: .nilOutInterceptorPipeline)
    }
  }
}
