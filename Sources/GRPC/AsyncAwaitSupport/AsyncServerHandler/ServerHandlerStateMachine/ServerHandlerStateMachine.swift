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
internal struct ServerHandlerStateMachine {
  private var state: Self.State

  init(userInfoRef: Ref<UserInfo>, context: CallHandlerContext) {
    self.state = .idle(.init(userInfoRef: userInfoRef, context: context))
  }

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
  fileprivate enum State {
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
  internal struct NextStateAndOutput<NextState, Output> {
    internal var nextState: NextState
    internal var output: Output

    internal init(nextState: NextState, output: Output) {
      self.nextState = nextState
      self.output = output
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.NextStateAndOutput where Output == Void {
  internal init(nextState: NextState) {
    self.nextState = nextState
    self.output = ()
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Idle {
  /// States which can be reached directly from 'Idle'.
  internal struct NextState {
    fileprivate let state: ServerHandlerStateMachine.State

    private init(_ state: ServerHandlerStateMachine.State) {
      self.state = state
    }

    internal static func idle(_ state: ServerHandlerStateMachine.Idle) -> Self {
      return Self(.idle(state))
    }

    internal static func handling(
      from: ServerHandlerStateMachine.Idle,
      context: GRPCAsyncServerCallContext
    ) -> Self {
      return Self(.handling(.init(from: from, context: context)))
    }

    internal static func finished(from: ServerHandlerStateMachine.Idle) -> Self {
      return Self(.finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Handling {
  /// States which can be reached directly from 'Handling'.
  internal struct NextState {
    fileprivate let state: ServerHandlerStateMachine.State

    private init(_ state: ServerHandlerStateMachine.State) {
      self.state = state
    }

    internal static func handling(_ state: ServerHandlerStateMachine.Handling) -> Self {
      return Self(.handling(state))
    }

    internal static func draining(from: ServerHandlerStateMachine.Handling) -> Self {
      return Self(.draining(.init(from: from)))
    }

    internal static func finished(from: ServerHandlerStateMachine.Handling) -> Self {
      return Self(.finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Draining {
  /// States which can be reached directly from 'Draining'.
  internal struct NextState {
    fileprivate let state: ServerHandlerStateMachine.State

    private init(_ state: ServerHandlerStateMachine.State) {
      self.state = state
    }

    internal static func draining(_ state: ServerHandlerStateMachine.Draining) -> Self {
      return Self(.draining(state))
    }

    internal static func finished(from: ServerHandlerStateMachine.Draining) -> Self {
      return Self(.finished(.init(from: from)))
    }
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension ServerHandlerStateMachine.Finished {
  /// States which can be reached directly from 'Finished'.
  internal struct NextState {
    fileprivate let state: ServerHandlerStateMachine.State

    private init(_ state: ServerHandlerStateMachine.State) {
      self.state = state
    }

    internal static func finished(_ state: ServerHandlerStateMachine.Finished) -> Self {
      return Self(.finished(state))
    }
  }
}
#endif // compiler(>=5.6)
