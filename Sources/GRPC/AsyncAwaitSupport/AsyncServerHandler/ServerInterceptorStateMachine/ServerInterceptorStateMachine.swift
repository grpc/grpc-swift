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
@usableFromInline
internal struct ServerInterceptorStateMachine {
  @usableFromInline
  internal private(set) var state: Self.State

  @inlinable
  init() {
    self.state = .intercepting(.init())
  }

  @inlinable
  mutating func interceptRequestMetadata() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptRequestMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptRequestMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptRequestMessage() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptRequestMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptRequestMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptRequestEnd() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptRequestEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptRequestEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedRequestMetadata() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedRequestMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedRequestMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedRequestMessage() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedRequestMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedRequestMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedRequestEnd() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedRequestEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedRequestEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptResponseMetadata() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptResponseMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptResponseMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptResponseMessage() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptResponseMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptResponseMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptResponseStatus() -> InterceptAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptResponseStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptResponseStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedResponseMetadata() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedResponseMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedResponseMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedResponseMessage() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedResponseMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedResponseMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func interceptedResponseStatus() -> InterceptedAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.interceptedResponseStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.interceptedResponseStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func cancel() -> CancelAction {
    switch self.state {
    case var .intercepting(intercepting):
      let nextStateAndOutput = intercepting.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }
}

extension ServerInterceptorStateMachine {
  /// The possible states the state machine may be in.
  @usableFromInline
  internal enum State {
    case intercepting(ServerInterceptorStateMachine.Intercepting)
    case finished(ServerInterceptorStateMachine.Finished)
  }
}

extension ServerInterceptorStateMachine {
  /// The next state to transition to and any output which may be produced as a
  /// result of a substate handling an action.
  @usableFromInline
  internal struct NextStateAndOutput<NextState, Output> {
    @usableFromInline
    internal var nextState: NextState
    @usableFromInline
    internal var output: Output

    @inlinable
    internal init(nextState: NextState, output: Output) {
      self.nextState = nextState
      self.output = output
    }
  }
}

extension ServerInterceptorStateMachine.NextStateAndOutput where Output == Void {
  internal init(nextState: NextState) {
    self.nextState = nextState
    self.output = ()
  }
}

extension ServerInterceptorStateMachine.Intercepting {
  /// States which can be reached directly from 'Intercepting'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerInterceptorStateMachine.State

    @inlinable
    init(_state: ServerInterceptorStateMachine.State) {
      self.state = _state
    }

    @usableFromInline
    internal static func intercepting(_ state: ServerInterceptorStateMachine.Intercepting) -> Self {
      return Self(_state: .intercepting(state))
    }

    @usableFromInline
    internal static func finished(from: ServerInterceptorStateMachine.Intercepting) -> Self {
      return Self(_state: .finished(.init(from: from)))
    }
  }
}

extension ServerInterceptorStateMachine.Finished {
  /// States which can be reached directly from 'Finished'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerInterceptorStateMachine.State

    @inlinable
    internal init(_state: ServerInterceptorStateMachine.State) {
      self.state = _state
    }

    @usableFromInline
    internal static func finished(_ state: ServerInterceptorStateMachine.Finished) -> Self {
      return Self(_state: .finished(state))
    }
  }
}
