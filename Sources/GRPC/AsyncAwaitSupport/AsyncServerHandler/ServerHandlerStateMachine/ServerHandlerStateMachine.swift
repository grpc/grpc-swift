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
@usableFromInline
internal struct ServerHandlerStateMachine {
  @usableFromInline
  internal private(set) var state: Self.State

  @inlinable
  init(userInfoRef: Ref<UserInfo>, context: CallHandlerContext) {
    self.state = .idle(.init(userInfoRef: userInfoRef, context: context))
  }

  @inlinable
  mutating func handleMetadata() -> HandleMetadataAction {
    switch self.state {
    case var .idle(idle):
      let nextStateAndOutput = idle.handleMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .handling(handling):
      let nextStateAndOutput = handling.handleMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.handleMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.handleMetadata()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func handleMessage() -> HandleMessageAction {
    switch self.state {
    case var .idle(idle):
      let nextStateAndOutput = idle.handleMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .handling(handling):
      let nextStateAndOutput = handling.handleMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.handleMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.handleMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func handleEnd() -> HandleEndAction {
    switch self.state {
    case var .idle(idle):
      let nextStateAndOutput = idle.handleEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .handling(handling):
      let nextStateAndOutput = handling.handleEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.handleEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.handleEnd()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func sendMessage() -> SendMessageAction {
    switch self.state {
    case var .handling(handling):
      let nextStateAndOutput = handling.sendMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.sendMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.sendMessage()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case .idle:
      preconditionFailure()
    }
  }

  @inlinable
  mutating func sendStatus() -> SendStatusAction {
    switch self.state {
    case var .handling(handling):
      let nextStateAndOutput = handling.sendStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.sendStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.sendStatus()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case .idle:
      preconditionFailure()
    }
  }

  @inlinable
  mutating func cancel() -> CancelAction {
    switch self.state {
    case var .idle(idle):
      let nextStateAndOutput = idle.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .handling(handling):
      let nextStateAndOutput = handling.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .draining(draining):
      let nextStateAndOutput = draining.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case var .finished(finished):
      let nextStateAndOutput = finished.cancel()
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    }
  }

  @inlinable
  mutating func handlerInvoked(context: GRPCAsyncServerCallContext) {
    switch self.state {
    case var .idle(idle):
      let nextStateAndOutput = idle.handlerInvoked(context: context)
      self.state = nextStateAndOutput.nextState.state
      return nextStateAndOutput.output
    case .handling:
      preconditionFailure()
    case .draining:
      preconditionFailure()
    case .finished:
      preconditionFailure()
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
  /// The possible states the state machine may be in.
  @usableFromInline
  internal enum State {
    case idle(ServerHandlerStateMachine.Idle)
    case handling(ServerHandlerStateMachine.Handling)
    case draining(ServerHandlerStateMachine.Draining)
    case finished(ServerHandlerStateMachine.Finished)
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine {
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.NextStateAndOutput where Output == Void {
  @inlinable
  internal init(nextState: NextState) {
    self.nextState = nextState
    self.output = ()
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Idle {
  /// States which can be reached directly from 'Idle'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerHandlerStateMachine.State

    @inlinable
    internal init(_state: ServerHandlerStateMachine.State) {
      self.state = _state
    }

    @inlinable
    internal static func idle(_ state: ServerHandlerStateMachine.Idle) -> Self {
      return Self(_state: .idle(state))
    }

    @inlinable
    internal static func handling(
      from: ServerHandlerStateMachine.Idle,
      context: GRPCAsyncServerCallContext
    ) -> Self {
      return Self(_state: .handling(.init(from: from, context: context)))
    }

    @inlinable
    internal static func finished(from: ServerHandlerStateMachine.Idle) -> Self {
      return Self(_state: .finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Handling {
  /// States which can be reached directly from 'Handling'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerHandlerStateMachine.State

    @inlinable
    internal init(_state: ServerHandlerStateMachine.State) {
      self.state = _state
    }

    @inlinable
    internal static func handling(_ state: ServerHandlerStateMachine.Handling) -> Self {
      return Self(_state: .handling(state))
    }

    @inlinable
    internal static func draining(from: ServerHandlerStateMachine.Handling) -> Self {
      return Self(_state: .draining(.init(from: from)))
    }

    @inlinable
    internal static func finished(from: ServerHandlerStateMachine.Handling) -> Self {
      return Self(_state: .finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Draining {
  /// States which can be reached directly from 'Draining'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerHandlerStateMachine.State

    @inlinable
    internal init(_state: ServerHandlerStateMachine.State) {
      self.state = _state
    }

    @inlinable
    internal static func draining(_ state: ServerHandlerStateMachine.Draining) -> Self {
      return Self(_state: .draining(state))
    }

    @inlinable
    internal static func finished(from: ServerHandlerStateMachine.Draining) -> Self {
      return Self(_state: .finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Finished {
  /// States which can be reached directly from 'Finished'.
  @usableFromInline
  internal struct NextState {
    @usableFromInline
    let state: ServerHandlerStateMachine.State

    @inlinable
    init(_state: ServerHandlerStateMachine.State) {
      self.state = _state
    }

    @inlinable
    internal static func finished(_ state: ServerHandlerStateMachine.Finished) -> Self {
      return Self(_state: .finished(state))
    }
  }
}
#endif // compiler(>=5.6)
