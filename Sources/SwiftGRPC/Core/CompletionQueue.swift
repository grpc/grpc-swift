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
  let type: CompletionType
  let success: Int32
  let tag: Int

  init(_ event: grpc_event) {
    type = CompletionType.completionType(event.type)
    success = event.success
    tag = Int(bitPattern: cgrpc_event_tag(event))
  }
}

/// A gRPC Completion Queue
class CompletionQueue {
  /// Optional user-provided name for the queue
  let name: String?

  /// Pointer to underlying C representation
  private let underlyingCompletionQueue: UnsafeMutableRawPointer

  /// Operation groups that are awaiting completion, keyed by tag
  private var operationGroups: [Int: OperationGroup] = [:]

  /// Mutex for synchronizing access to operationGroups
  private let operationGroupsMutex: Mutex = Mutex()
  
  private var hasBeenShutdown = false

  /// Initializes a CompletionQueue
  ///
  /// - Parameter cq: the underlying C representation
  init(underlyingCompletionQueue: UnsafeMutableRawPointer, name: String? = nil) {
    // The underlying completion queue is NOT OWNED by this class, so we don't dealloc it in a deinit
    self.underlyingCompletionQueue = underlyingCompletionQueue
    self.name = name
  }
  
  deinit {
    operationGroupsMutex.synchronize {
      hasBeenShutdown = true
    }
    cgrpc_completion_queue_shutdown(underlyingCompletionQueue)
    cgrpc_completion_queue_drain(underlyingCompletionQueue)
    grpc_completion_queue_destroy(underlyingCompletionQueue)
  }

  /// Waits for an operation group to complete
  ///
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a grpc_completion_type code indicating the result of waiting
  func wait(timeout: TimeInterval) -> CompletionQueueEvent {
    let event = cgrpc_completion_queue_get_next_event(underlyingCompletionQueue, timeout)
    return CompletionQueueEvent(event)
  }

  /// Register an operation group for handling upon completion. Will throw if the queue has been shutdown already.
  ///
  /// - Parameter operationGroup: the operation group to handle.
  func register(_ operationGroup: OperationGroup, onSuccess: () throws -> Void) throws {
    try operationGroupsMutex.synchronize {
      guard !hasBeenShutdown
        else { throw CallError.completionQueueShutdown }
      operationGroups[operationGroup.tag] = operationGroup
      try onSuccess()
    }
  }

  /// Runs a completion queue and call a completion handler when finished
  ///
  /// - Parameter completion: a completion handler that is called when the queue stops running
  func runToCompletion(completion: (() -> Void)?) {
    // run the completion queue on a new background thread
    let spinloopThreadQueue = DispatchQueue(label: "SwiftGRPC.CompletionQueue.runToCompletion.spinloopThread")
    spinloopThreadQueue.async {
      spinloop: while true {
        let event = cgrpc_completion_queue_get_next_event(self.underlyingCompletionQueue, 600)
        switch event.type {
        case GRPC_OP_COMPLETE:
          let tag = Int(bitPattern:cgrpc_event_tag(event))
          self.operationGroupsMutex.lock()
          let operationGroup = self.operationGroups[tag]
          self.operationGroupsMutex.unlock()
          if let operationGroup = operationGroup {
            // call the operation group completion handler
            operationGroup.success = (event.success == 1)
            operationGroup.completion?(operationGroup)
            self.operationGroupsMutex.synchronize {
              self.operationGroups[tag] = nil
            }
          } else {
            print("CompletionQueue.runToCompletion error: operation group with tag \(tag) not found")
          }
        case GRPC_QUEUE_SHUTDOWN:
          self.operationGroupsMutex.lock()
          let currentOperationGroups = self.operationGroups
          self.operationGroups = [:]
          self.operationGroupsMutex.unlock()
          
          for operationGroup in currentOperationGroups.values {
            operationGroup.success = false
            operationGroup.completion?(operationGroup)
          }
          break spinloop
        case GRPC_QUEUE_TIMEOUT:
          continue spinloop
        default:
          print("CompletionQueue.runToCompletion error: unknown event type \(event.type)")
          break spinloop
        }
      }
      // when the queue stops running, call the queue completion handler
      completion?()
    }
  }

  /// Runs a completion queue
  func run() {
    runToCompletion(completion: nil)
  }

  /// Shuts down a completion queue
  func shutdown() {
    var needsShutdown = false
    operationGroupsMutex.synchronize {
      if !hasBeenShutdown {
        needsShutdown = true
        hasBeenShutdown = true
      }
    }
    if needsShutdown {
      cgrpc_completion_queue_shutdown(underlyingCompletionQueue)
    }
  }
}
