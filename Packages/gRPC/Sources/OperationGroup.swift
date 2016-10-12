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
internal class OperationGroup {

  /// Used to generate unique tags for OperationGroups
  private static var nextTag : Int64 = 1

  /// Automatically-assigned tag that is used by the completion queue that watches this group.
  internal var tag : Int64

  /// The call associated with the operation group. Retained while the operations are running.
  private var call : Call

  /// An array of operation objects that are passed into the initializer.
  private var operations : [Operation]

  /// An array of observers used to watch the operation
  private var underlyingObservers : [UnsafeMutableRawPointer] = []

  /// Pointer to underlying C representation
  internal var underlyingOperations : UnsafeMutableRawPointer?

  /// Completion handler that is called when the group completes
  internal var completion : ((OperationGroup) throws -> Void)

  /// Indicates that the OperationGroup completed successfully
  internal var success : Bool = false

  /// Creates the underlying observer needed to run an operation
  ///
  /// - Parameter: operation: the operation to observe
  /// - Returns: the observer
  private func underlyingObserverForOperation(operation: Operation) -> UnsafeMutableRawPointer {
    var underlyingObserver : UnsafeMutableRawPointer
    switch operation {
    case .sendInitialMetadata(let metadata):
      underlyingObserver = cgrpc_observer_create_send_initial_metadata(metadata.underlyingArray)!
    case .sendMessage(let message):
      underlyingObserver = cgrpc_observer_create_send_message()!
      cgrpc_observer_send_message_set_message(underlyingObserver, message.underlyingByteBuffer)
    case .sendCloseFromClient:
      underlyingObserver = cgrpc_observer_create_send_close_from_client()!
    case .sendStatusFromServer(let statusCode, let statusMessage, let metadata):
      underlyingObserver = cgrpc_observer_create_send_status_from_server(metadata.underlyingArray)!
      cgrpc_observer_send_status_from_server_set_status(underlyingObserver, Int32(statusCode))
      cgrpc_observer_send_status_from_server_set_status_details(underlyingObserver, statusMessage)
    case .receiveInitialMetadata:
      underlyingObserver = cgrpc_observer_create_recv_initial_metadata()!
    case .receiveMessage:
      underlyingObserver = cgrpc_observer_create_recv_message()!
    case .receiveStatusOnClient:
      underlyingObserver = cgrpc_observer_create_recv_status_on_client()!
    case .receiveCloseOnServer:
      underlyingObserver = cgrpc_observer_create_recv_close_on_server()!
    }
    return underlyingObserver
  }

  /// Initializes an OperationGroup representation
  ///
  /// - Parameter operations: an array of operations
  init(call: Call,
       operations: [Operation],
       completion: @escaping ((OperationGroup) throws -> Void)) {
    self.call = call
    self.operations = operations
    self.completion = completion
    // set tag
    let mutex = OperationGroupTagLock.sharedInstance.mutex
    mutex.lock()
    self.tag = OperationGroup.nextTag
    OperationGroup.nextTag += 1
    mutex.unlock()
    // create observers
    for operation in operations {
      self.underlyingObservers.append(self.underlyingObserverForOperation(operation: operation))
    }
    // create operations
    self.underlyingOperations = cgrpc_operations_create()
    cgrpc_operations_reserve_space_for_operations(self.underlyingOperations, Int32(operations.count))
    for underlyingObserver in underlyingObservers {
      cgrpc_operations_add_operation(self.underlyingOperations, underlyingObserver)
    }
  }

  deinit {
    for underlyingObserver in underlyingObservers {
      cgrpc_observer_destroy(underlyingObserver);
    }
    cgrpc_operations_destroy(underlyingOperations);
  }

  /// WARNING: The following assumes that at most one operation of each type is in the group.
  
  /// Gets the message that was received
  ///
  /// - Returns: message
  internal func receivedMessage() -> ByteBuffer? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveMessage:
        if let b = cgrpc_observer_recv_message_get_message(underlyingObservers[i]) {
          return ByteBuffer(underlyingByteBuffer:b)
        } else {
          return nil
        }
      default: continue
      }
    }
    return nil
  }

  /// Gets the initial metadata that was received
  ///
  /// - Returns: metadata
  internal func receivedInitialMetadata() -> Metadata? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveInitialMetadata:
        return Metadata(underlyingArray:cgrpc_observer_recv_initial_metadata_get_metadata(underlyingObservers[i]));
      default:
        continue
      }
    }
    return nil
  }

  /// Gets the status code that was received
  ///
  /// - Returns: status code
  internal func receivedStatusCode() -> Int? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveStatusOnClient:
        return cgrpc_observer_recv_status_on_client_get_status(underlyingObservers[i])
      default:
        continue
      }
    }
    return nil
  }

  /// Gets the status message that was received
  ///
  /// - Returns: status message
  internal func receivedStatusMessage() -> String? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveStatusOnClient:
        return String(cString:cgrpc_observer_recv_status_on_client_get_status_details(underlyingObservers[i]),
                      encoding:String.Encoding.utf8)!
      default:
        continue
      }
    }
    return nil
  }

  /// Gets the trailing metadata that was received
  ///
  /// - Returns: metadata
  internal func receivedTrailingMetadata() -> Metadata? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveStatusOnClient:
        return Metadata(underlyingArray:cgrpc_observer_recv_status_on_client_get_metadata(underlyingObservers[i]));
      default:
        continue
      }
    }
    return nil
  }
}

