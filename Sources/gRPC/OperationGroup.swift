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
#endif

/// A collection of gRPC operations
internal class OperationGroup {

  /// A mutex for synchronizing tag generation
  static let tagMutex = Mutex()

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
      cgrpc_observer_send_status_from_server_set_status(underlyingObserver, Int32(statusCode.rawValue))
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
    // set tag to a unique value (per execution)
    OperationGroup.tagMutex.lock()
    self.tag = OperationGroup.nextTag
    OperationGroup.nextTag += 1
    OperationGroup.tagMutex.unlock()
    // create underlying observers and operations
    self.underlyingOperations = cgrpc_operations_create()
    cgrpc_operations_reserve_space_for_operations(self.underlyingOperations, Int32(operations.count))
    for operation in operations {
      let underlyingObserver = self.underlyingObserverForOperation(operation: operation)
      self.underlyingObservers.append(underlyingObserver)
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

  /// Gets initial metadata that was received
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

  /// Gets a status code that was received
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

  /// Gets a status message that was received
  ///
  /// - Returns: status message
  internal func receivedStatusMessage() -> String? {
    for (i, operation) in operations.enumerated() {
      switch (operation) {
      case .receiveStatusOnClient:
        if let string = cgrpc_observer_recv_status_on_client_copy_status_details(underlyingObservers[i]) {
          defer {
            cgrpc_free_copied_string(string);
          }
          return String(cString:string, encoding:String.Encoding.utf8)!
        } else {
          return nil
        }
      default:
        continue
      }
    }
    return nil
  }

  /// Gets trailing metadata that was received
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

