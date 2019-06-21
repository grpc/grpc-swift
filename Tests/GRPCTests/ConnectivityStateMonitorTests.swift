/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
@testable import GRPC
import XCTest

class ConnectivityStateMonitorTests: XCTestCase {
  var monitor = ConnectivityStateMonitor(delegate: nil)

  // Ensure `.idle` isn't first since it is the initial state and we only trigger callbacks
  // when the state changes, not when the state is set.
  let states: [ConnectivityState] = [.connecting, .ready, .transientFailure, .shutdown, .idle]

  func testDelegateOnlyCalledForChanges() {
    let recorder = StateRecordingDelegate()
    self.monitor.delegate = recorder

    self.monitor.state = .connecting
    self.monitor.state = .ready
    self.monitor.state = .ready
    self.monitor.state = .shutdown

    XCTAssertEqual(recorder.states, [.connecting, .ready, .shutdown])
  }

  func testOnNextIsOnlyInvokedOnce() {
    for state in self.states {
      let currentState = self.monitor.state

      var calls = 0
      self.monitor.onNext(state: state) {
        calls += 1
      }

      // Trigger the callback.
      self.monitor.state = state
      XCTAssertEqual(calls, 1)

      // Go back and forth; the callback should not be triggered again.
      self.monitor.state = currentState
      self.monitor.state = state
      XCTAssertEqual(calls, 1)
    }
  }

  func testRemovingCallbacks() {
    for state in self.states {
      self.monitor.onNext(state: state) {
        XCTFail("Callback unexpectedly called")
      }

      self.monitor.onNext(state: state, callback: nil)
      self.monitor.state = state
    }
  }

  func testMultipleCallbacksRegistered() {
    var calls = 0
    self.states.forEach {
      self.monitor.onNext(state: $0) {
        calls += 1
      }
    }

    self.states.forEach {
      self.monitor.state = $0
    }

    XCTAssertEqual(calls, self.states.count)
  }
}

extension ConnectivityStateMonitorTests {
  /// A `ConnectivityStateDelegate` which each new state.
  class StateRecordingDelegate: ConnectivityStateDelegate {
    var states: [ConnectivityState] = []
    func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
      self.states.append(newState)
    }
  }
}
