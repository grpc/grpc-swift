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

/// A type indicating the kind of event returned by the completion queue
enum CompletionType {
  case queueShutdown
  case queueTimeout
  case complete
  case unknown

  fileprivate static func completionType(_ value: grpc_completion_type) -> CompletionType {
    switch value {
    case GRPC_QUEUE_SHUTDOWN:
      return .queueShutdown
    case GRPC_QUEUE_TIMEOUT:
      return .queueTimeout
    case GRPC_OP_COMPLETE:
      return .complete
    default:
      return .unknown
    }
  }
}

/// An event that is returned by the completion queue
struct CompletionQueueEvent {
  var type: CompletionType
  var success: Int32
  var tag: Int64

  init(_ event: grpc_event) {
    type = CompletionType.completionType(event.type)
    success = event.success
    tag = cgrpc_event_tag(event)
  }
}

/// A gRPC Completion Queue
class CompletionQueue {
  /// Optional user-provided name for the queue
  var name: String?

  /// Pointer to underlying C representation
  private var underlyingCompletionQueue: UnsafeMutableRawPointer

  /// Operation groups that are awaiting completion, keyed by tag
  private var operationGroups: [Int64: OperationGroup] = [:]

  /// Mutex for synchronizing access to operationGroups
  private var operationGroupsMutex: Mutex = Mutex()

  /// Initializes a CompletionQueue
  ///
  /// - Parameter cq: the underlying C representation
  init(underlyingCompletionQueue: UnsafeMutableRawPointer) {
    // The underlying completion queue is NOT OWNED by this class, so we don't dealloc it in a deinit
    self.underlyingCompletionQueue = underlyingCompletionQueue
  }

  /// Waits for an operation group to complete
  ///
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a grpc_completion_type code indicating the result of waiting
  func wait(timeout: TimeInterval) -> CompletionQueueEvent {
    let event = cgrpc_completion_queue_get_next_event(underlyingCompletionQueue, timeout)
    return CompletionQueueEvent(event)
  }

  /// Register an operation group for handling upon completion
  ///
  /// - Parameter operationGroup: the operation group to handle
  func register(_ operationGroup: OperationGroup) {
    operationGroupsMutex.lock()
    operationGroups[operationGroup.tag] = operationGroup
    operationGroupsMutex.unlock()
  }

  /// Runs a completion queue and call a completion handler when finished
  ///
  /// - Parameter callbackQueue: a DispatchQueue to use to call the completion handler
  /// - Parameter completion: a completion handler that is called when the queue stops running
  func runToCompletion(callbackQueue: DispatchQueue? = DispatchQueue.main,
                                _ completion: @escaping () -> Void) {
    // run the completion queue on a new background thread
    DispatchQueue.global().async {
      var running = true
      while running {
        let event = cgrpc_completion_queue_get_next_event(self.underlyingCompletionQueue, -1.0)
        switch event.type {
        case GRPC_OP_COMPLETE:
          let tag = cgrpc_event_tag(event)
          self.operationGroupsMutex.lock()
          let operationGroup = self.operationGroups[tag]
          self.operationGroupsMutex.unlock()
          if let operationGroup = operationGroup {
            // call the operation group completion handler
            do {
              operationGroup.success = (event.success == 1)
              try operationGroup.completion(operationGroup)
            } catch (let callError) {
              print("CompletionQueue runToCompletion: grpc error \(callError)")
            }
            self.operationGroupsMutex.lock()
            self.operationGroups[tag] = nil
            self.operationGroupsMutex.unlock()
          }
          break
        case GRPC_QUEUE_SHUTDOWN:
          running = false
          do {
            for operationGroup in self.operationGroups.values {
              operationGroup.success = false
              try operationGroup.completion(operationGroup)
            }
          } catch (let callError) {
            print("CompletionQueue runToCompletion: grpc error \(callError)")
          }
          self.operationGroupsMutex.lock()
          self.operationGroups = [:]
          self.operationGroupsMutex.unlock()
          break
        case GRPC_QUEUE_TIMEOUT:
          break
        default:
          break
        }
      }
      if let callbackQueue = callbackQueue {
        callbackQueue.async {
          // when the queue stops running, call the queue completion handler
          completion()
        }
      }
    }
  }

  /// Runs a completion queue
  func run() {
    runToCompletion(callbackQueue: nil) {}
  }

  /// Shuts down a completion queue
  func shutdown() {
    cgrpc_completion_queue_shutdown(underlyingCompletionQueue)
  }
}
