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
import Logging

class ConnectivityStateMonitorTests: GRPCTestCase {
  // Ensure `.idle` isn't first since it is the initial state and we only trigger callbacks
  // when the state changes, not when the state is set.
  let states: [ConnectivityState] = [.connecting, .ready, .transientFailure, .shutdown, .idle]

  func testDelegateOnlyCalledForChanges() {
    let recorder = RecordingConnectivityDelegate()

    recorder.expectChanges(3) { changes in
      XCTAssertEqual(changes, [
        Change(from: .idle, to: .connecting),
        Change(from: .connecting, to: .ready),
        Change(from: .ready, to: .shutdown)
      ])
    }

    let monitor = ConnectivityStateMonitor(delegate: recorder, queue: nil)
    monitor.delegate = recorder

    monitor.updateState(to: .connecting, logger: self.logger)
    monitor.updateState(to: .ready, logger: self.logger)
    monitor.updateState(to: .ready, logger: self.logger)
    monitor.updateState(to: .shutdown, logger: self.logger)

    recorder.waitForExpectedChanges(timeout: .seconds(1))
  }
}
