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
#endif

/// A gRPC Completion Queue
public class CompletionQueue {

  /// Pointer to underlying C representation
  var cq : UnsafeMutableRawPointer!

  /// Operation groups that are awaiting completion, keyed by tag
  public var operationGroups : [Int64 : OperationGroup] = [:]

  /// Initializes a CompletionQueue
  ///
  /// - Parameter cq: the underlying C representation
  init(cq: UnsafeMutableRawPointer) {
    self.cq = cq // NOT OWNED, so we don't dealloc it
  }

  /// Waits for an event to complete
  ///
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a grpc_completion_type code indicating the result of waiting
  public func waitForCompletion(timeout: Double) -> grpc_event {
    return cgrpc_completion_queue_get_next_event(cq, timeout);
  }

  public func run() {
    DispatchQueue.global().async {
      while (true) {
        let event = cgrpc_completion_queue_get_next_event(self.cq, -1.0)
        switch (event.type) {
        case GRPC_OP_COMPLETE:
          let tag = cgrpc_event_tag(event)
          if let operations = self.operationGroups[tag] {
            operations.completion(event)
            self.operationGroups[tag] = nil
          }
          continue
        case GRPC_QUEUE_SHUTDOWN:
          // grpc_completion_queue_destroy(unmanagedQueue);
          break
        case GRPC_QUEUE_TIMEOUT:
          continue
        default:
          continue
        }
      }
    }
  }
}
