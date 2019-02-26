/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
#if SWIFT_PACKAGE
import CgRPC
import Dispatch
#endif
import Foundation

extension Channel {
  /// Provides an interface for observing the connectivity of a given channel.
  final class ConnectivityObserver {
    private let mutex = Mutex()
    private let completionQueue: CompletionQueue
    private let underlyingChannel: UnsafeMutableRawPointer
    private let underlyingCompletionQueue: UnsafeMutableRawPointer
    private var callbacks = [(ConnectivityState) -> Void]()
    private var hasBeenShutdown = false

    init(underlyingChannel: UnsafeMutableRawPointer) {
      self.underlyingChannel = underlyingChannel
      self.underlyingCompletionQueue = cgrpc_completion_queue_create_for_next()
      self.completionQueue = CompletionQueue(underlyingCompletionQueue: self.underlyingCompletionQueue,
                                             name: "Connectivity State")
      self.run()
    }

    deinit {
      self.shutdown()
    }

    func addConnectivityObserver(callback: @escaping (ConnectivityState) -> Void) {
      self.mutex.synchronize {
        self.callbacks.append(callback)
      }
    }

    func shutdown() {
      self.mutex.synchronize {
        guard !self.hasBeenShutdown else { return }

        self.hasBeenShutdown = true
        self.completionQueue.shutdown()
      }
    }

    // MARK: - Private

    private func run() {
      let spinloopThreadQueue = DispatchQueue(label: "SwiftGRPC.ConnectivityObserver.run.spinloopThread")
      var lastState = ConnectivityState(cgrpc_channel_check_connectivity_state(self.underlyingChannel, 0))
      spinloopThreadQueue.async {
        while (self.mutex.synchronize { !self.hasBeenShutdown }) {
          guard let underlyingState = lastState.underlyingState else { return }

          let deadline: TimeInterval = 0.2
          cgrpc_channel_watch_connectivity_state(self.underlyingChannel, self.underlyingCompletionQueue,
                                                 underlyingState, deadline, nil)

          let event = self.completionQueue.wait(timeout: deadline)
          guard (self.mutex.synchronize { !self.hasBeenShutdown }) else {
            return
          }

          switch event.type {
          case .complete:
            let newState = ConnectivityState(cgrpc_channel_check_connectivity_state(self.underlyingChannel, 0))
            guard newState != lastState else { continue }

            let callbacks = self.mutex.synchronize { Array(self.callbacks) }
            lastState = newState
            callbacks.forEach { callback in callback(newState) }

          case .queueShutdown:
            return

          default:
            continue
          }
        }
      }
    }
  }
}
