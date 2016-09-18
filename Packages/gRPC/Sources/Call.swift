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
import Foundation

/// Singleton class that provides a mutex for synchronizing calls to cgrpc_call_perform()
private class CallLock {
  var mutex : Mutex
  private init() {
    mutex = Mutex()
  }
  static let sharedInstance = CallLock()
}

/// A gRPC API call
public class Call {

  /// Pointer to underlying C representation
  private var call : UnsafeMutableRawPointer!

  /// Completion queue used for call
  private var completionQueue: CompletionQueue

  /// True if this instance is responsible for deleting the underlying C representation
  private var owned : Bool

  /// A queue of pending messages to send over the call
  private var pendingMessages : Array<Data>

  /// True if a message write operation is underway
  private var writing : Bool

  /// Initializes a Call representation
  ///
  /// - Parameter call: the underlying C representation
  /// - Parameter owned: true if this instance is responsible for deleting the underlying call
  init(call: UnsafeMutableRawPointer, owned: Bool, completionQueue: CompletionQueue) {
    self.call = call
    self.owned = owned
    self.completionQueue = completionQueue
    self.pendingMessages = []
    self.writing = false
  }

  deinit {
    if (owned) {
      cgrpc_call_destroy(call)
    }
  }

  /// Initiate performance of a call without waiting for completion
  ///
  /// - Parameter operations: array of operations to be performed
  /// - Parameter tag: integer tag that will be attached to these operations
  /// - Returns: the result of initiating the call
  func performOperations(operations: OperationGroup,
                         tag: Int64,
                         completionQueue: CompletionQueue)
    -> grpc_call_error {
      let mutex = CallLock.sharedInstance.mutex
      mutex.lock()
      let error = cgrpc_call_perform(call, operations.operations, tag)
      mutex.unlock()
      return error
  }


  /// Performs a nonstreaming gRPC API call
  ///
  /// - Parameter message: a ByteBuffer containing the message to send
  /// - Parameter metadata: metadata to send with the call
  /// - Returns: a CallResponse object containing results of the call
  public func performNonStreamingCall(messageData: Data,
                                      metadata: Metadata,
                                      completion: @escaping ((CallResponse) -> Void)) -> Void   {

    let messageBuffer = ByteBuffer(data:messageData)

    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:metadata);
    let operation_sendMessage = Operation_SendMessage(message:messageBuffer)
    let operation_sendCloseFromClient = Operation_SendCloseFromClient()
    let operation_receiveInitialMetadata = Operation_ReceiveInitialMetadata()
    let operation_receiveStatusOnClient = Operation_ReceiveStatusOnClient()
    let operation_receiveMessage = Operation_ReceiveMessage()

    let group = OperationGroup(call:self,
                               operations:[operation_sendInitialMetadata,
                                           operation_sendMessage,
                                           operation_sendCloseFromClient,
                                           operation_receiveInitialMetadata,
                                           operation_receiveStatusOnClient,
                                           operation_receiveMessage])
    { (success) in
      if success {
        let response = CallResponse(status:operation_receiveStatusOnClient.status(),
                                    statusDetails:operation_receiveStatusOnClient.statusDetails(),
                                    message:operation_receiveMessage.message(),
                                    initialMetadata:operation_receiveInitialMetadata.metadata(),
                                    trailingMetadata:operation_receiveStatusOnClient.metadata())
        completion(response)
      } else {
        completion(CallResponse())
      }
    }
    let call_error = self.perform(call: self, operations: group)
    if call_error != GRPC_CALL_OK {
      print ("call error = \(call_error)")
    }
  }

  // perform a group of operations (used internally)
  private func perform(call: Call, operations: OperationGroup) -> grpc_call_error {
    self.completionQueue.operationGroups[operations.tag] = operations
    return call.performOperations(operations:operations,
                                  tag:operations.tag,
                                  completionQueue: self.completionQueue)
  }

  // start a streaming connection
  public func start(metadata: Metadata) {
    self.sendInitialMetadata(metadata: metadata)
    self.receiveInitialMetadata()
    self.receiveStatus()
  }

  // send a message over a streaming connection
  public func sendMessage(data: Data) {
    DispatchQueue.main.async {
      if self.writing {
        self.pendingMessages.append(data)
      } else {
        self.writing = true
        self.sendWithoutBlocking(data: data)
      }
    }
  }

  private func sendWithoutBlocking(data: Data) {
    let messageBuffer = ByteBuffer(data:data)
    let operation_sendMessage = Operation_SendMessage(message:messageBuffer)
    let operations = OperationGroup(call:self, operations:[operation_sendMessage])
    { (event) in

      // if the event failed, shut down


      DispatchQueue.main.async {
      if self.pendingMessages.count > 0 {
        let nextMessage = self.pendingMessages.first!
        self.pendingMessages.removeFirst()
        self.sendWithoutBlocking(data: nextMessage)
      } else {
        self.writing = false
      }
      }
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }


  // receive a message over a streaming connection
  public func receiveMessage(callback:@escaping ((Data!) -> Void)) -> Void {
    let operation_receiveMessage = Operation_ReceiveMessage()
    let operations = OperationGroup(call:self, operations:[operation_receiveMessage])
    { (event) in
      if let messageBuffer = operation_receiveMessage.message() {
        callback(messageBuffer.data())
      }
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  // send initial metadata over a streaming connection
  private func sendInitialMetadata(metadata: Metadata) {
    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:metadata);
    let operations = OperationGroup(call:self, operations:[operation_sendInitialMetadata])
    { (success) in
      if (success) {
        print("call successful")
      } else {
        return
      }
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error: \(call_error)")
    }
  }

  // receive initial metadata from a streaming connection
  private func receiveInitialMetadata() {
    let operation_receiveInitialMetadata = Operation_ReceiveInitialMetadata()
    let operations = OperationGroup(call:self, operations:[operation_receiveInitialMetadata])
    { (event) in
      let initialMetadata = operation_receiveInitialMetadata.metadata()
      for j in 0..<initialMetadata.count() {
        print("Received initial metadata -> " + initialMetadata.key(index:j) + " : " + initialMetadata.value(index:j))
      }
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  // receive status from a streaming connection
  private func receiveStatus() {
    let operation_receiveStatus = Operation_ReceiveStatusOnClient()
    let operations = OperationGroup(call:self,
                                    operations:[operation_receiveStatus])
    { (event) in
      print("status = \(operation_receiveStatus.status()), \(operation_receiveStatus.statusDetails())")
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }

  // close a streaming connection
  public func close(completion:@escaping (() -> Void)) {
    let operation_sendCloseFromClient = Operation_SendCloseFromClient()
    let operations = OperationGroup(call:self, operations:[operation_sendCloseFromClient])
    { (event) in
      completion()
    }
    let call_error = self.perform(call:self, operations:operations)
    if call_error != GRPC_CALL_OK {
      print("call error \(call_error)")
    }
  }
}
