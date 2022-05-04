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
  internal struct Finished {
    typealias NextStateAndOutput<Output> = ServerHandlerStateMachine.NextStateAndOutput<
      ServerHandlerStateMachine.Finished.NextState,
      Output
    >

    internal init(from state: ServerHandlerStateMachine.Idle) {}
    internal init(from state: ServerHandlerStateMachine.Handling) {}
    internal init(from state: ServerHandlerStateMachine.Draining) {}

    mutating func handleMetadata() -> Self.NextStateAndOutput<HandleMetadataAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    mutating func handleMessage() -> Self.NextStateAndOutput<HandleMessageAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    mutating func handleEnd() -> Self.NextStateAndOutput<HandleEndAction> {
      return .init(nextState: .finished(self), output: .cancel)
    }

    mutating func sendMessage() -> Self.NextStateAndOutput<SendMessageAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    mutating func sendStatus() -> Self.NextStateAndOutput<SendStatusAction> {
      return .init(nextState: .finished(self), output: .drop)
    }

    mutating func cancel() -> Self.NextStateAndOutput<CancelAction> {
      return .init(nextState: .finished(self), output: .cancelAndNilOutHandlerComponents)
    }
  }
}
#endif // compiler(>=5.6)
