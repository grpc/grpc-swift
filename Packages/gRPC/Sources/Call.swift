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

/// Singleton class that provides a mutex for synchronizing calls to cgrpc_call_perform()
private class CallLock {
  var mutex : Mutex
  init() {
    mutex = Mutex()
  }
  static let sharedInstance = CallLock()
}

/// A gRPC API call
public class Call {

  /// Pointer to underlying C representation
  private var call : UnsafeMutableRawPointer!

  /// True if this instance is responsible for deleting the underlying C representation
  private var owned : Bool

  /// Initializes a Call representation
  ///
  /// - Parameter call: the underlying C representation
  /// - Parameter owned: true if this instance is responsible for deleting the underlying call
  init(call: UnsafeMutableRawPointer, owned: Bool) {
    self.call = call
    self.owned = owned
  }

  // coming soon
  init(call: UnsafeMutableRawPointer,
       requestsWriter: Writer,
       responsesWritable: Writable) {
    self.call = call
    self.owned = true
  }

  deinit {
    if (owned) {
      cgrpc_call_destroy(call)
    }
  }

  // coming soon
  func start() {

  }

  /// Initiate performance of a call without waiting for completion
  ///
  /// - Parameter operations: array of operations to be performed
  /// - Parameter tag: integer tag that will be attached to these operations
  /// - Returns: the result of initiating the call
  public func performOperations(operations: OperationGroup,
                                tag: Int64,
                                completionQueue: CompletionQueue)
    -> grpc_call_error {
      let mutex = CallLock.sharedInstance.mutex
      mutex.lock()
      let error = cgrpc_call_perform(call, operations.operations, tag)
      mutex.unlock()
      return error
  }
}
