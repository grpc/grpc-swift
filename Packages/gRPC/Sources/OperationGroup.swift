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

/// Singleton class that provides a mutex for synchronizing tag generation
private class OperationGroupTagLock {
  var mutex : Mutex
  private init() {
    mutex = Mutex()
  }
  static let sharedInstance = OperationGroupTagLock()
}

/// A collection of gRPC operations
class OperationGroup {

  /// Used to generate unique tags for OperationGroups
  static var nextTag : Int64 = 1

  /// Automatically-assigned tag that is used with the completion queue.
  var tag : Int64

  /// The call associated with the operation group. Retained while the operations are running.
  var call : Call

  /// An array of operation objects that are passed into the initializer
  var operationsArray : [Operation]?

  /// Pointer to underlying C representation
  var underlyingOperations : UnsafeMutableRawPointer

  /// Completion handler that is called when the group completes
  var completion : ((Bool) throws -> Void)

  /// Initializes an OperationGroup representation
  ///
  /// - Parameter operations: an array of operations
  init(call: Call,
       operations: [Operation],
       completion: @escaping ((Bool) throws -> Void)) {
    self.call = call
    self.operationsArray = operations
    self.underlyingOperations = cgrpc_operations_create()
    cgrpc_operations_reserve_space_for_operations(self.underlyingOperations, Int32(operations.count))
    for operation in operations {
      cgrpc_operations_add_operation(self.underlyingOperations, operation.underlyingObserver)
    }
    self.completion = completion
    let mutex = OperationGroupTagLock.sharedInstance.mutex
    mutex.lock()
    self.tag = OperationGroup.nextTag
    OperationGroup.nextTag += 1
    mutex.unlock()
  }
}

