/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
#if SWIFT_PACKAGE
  import CgRPC
  import Dispatch
#endif
import Foundation

/// A type indicating the kind of event returned by the completion queue
internal enum CompletionType {
  case queueShutdown
  case queueTimeout
  case complete
  case unknown

  fileprivate static func completionType(_ value: grpc_completion_type) -> CompletionType {
    switch(value) {
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
internal struct CompletionQueueEvent {
  internal var type: CompletionType
  internal var success: Int32
  internal var tag: Int64

  internal init(_ event: grpc_event) {
    type = CompletionType.completionType(event.type)
    success = event.success
    tag = cgrpc_event_tag(event)
  }
}

/// A gRPC Completion Queue
internal class CompletionQueue {

  /// Optional user-provided name for the queue
  internal var name : String?

  /// Pointer to underlying C representation
  private var underlyingCompletionQueue : UnsafeMutableRawPointer

  /// Operation groups that are awaiting completion, keyed by tag
  private var operationGroups : [Int64 : OperationGroup] = [:]

  /// Mutex for synchronizing access to operationGroups
  private var operationGroupsMutex : Mutex = Mutex()

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
  internal func wait(timeout: TimeInterval) -> CompletionQueueEvent {
    let event = cgrpc_completion_queue_get_next_event(underlyingCompletionQueue, timeout);
    return CompletionQueueEvent(event)
  }

  /// Register an operation group for handling upon completion
  ///
  /// - Parameter operationGroup: the operation group to handle
  internal func register(_ operationGroup:OperationGroup) -> Void {
    operationGroupsMutex.lock()
    operationGroups[operationGroup.tag] = operationGroup
    operationGroupsMutex.unlock()
  }

  /// Runs a completion queue and call a completion handler when finished
  ///
  /// - Parameter callbackQueue: a DispatchQueue to use to call the completion handler
  /// - Parameter completion: a completion handler that is called when the queue stops running
  internal func runToCompletion(callbackQueue:DispatchQueue? = DispatchQueue.main,
                                _ completion:@escaping () -> Void) {
    // run the completion queue on a new background thread
    DispatchQueue.global().async {
      var running = true
      while (running) {
        let event = cgrpc_completion_queue_get_next_event(self.underlyingCompletionQueue, -1.0)
        switch (event.type) {
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
  internal func run() -> Void {
    self.runToCompletion(callbackQueue:nil) {}
  }

  /// Shuts down a completion queue
  internal func shutdown() -> Void {
    cgrpc_completion_queue_shutdown(underlyingCompletionQueue)
  }
}
