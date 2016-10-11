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

public enum CallError : Error {
  case ok
  case unknown
  case notOnServer
  case notOnClient
  case alreadyAccepted
  case alreadyInvoked
  case notInvoked
  case alreadyFinished
  case tooManyOperations
  case invalidFlags
  case invalidMetadata
  case invalidMessage
  case notServerCompletionQueue
  case batchTooBig
  case payloadTypeMismatch

  static func callError(grpcCallError error: grpc_call_error) -> CallError {
    switch(error) {
    case GRPC_CALL_OK:
      return .ok
    case GRPC_CALL_ERROR:
      return .unknown
    case GRPC_CALL_ERROR_NOT_ON_SERVER:
      return .notOnServer
    case GRPC_CALL_ERROR_NOT_ON_CLIENT:
      return .notOnClient
    case GRPC_CALL_ERROR_ALREADY_ACCEPTED:
      return .alreadyAccepted
    case GRPC_CALL_ERROR_ALREADY_INVOKED:
      return .alreadyInvoked
    case GRPC_CALL_ERROR_NOT_INVOKED:
      return .notInvoked
    case GRPC_CALL_ERROR_ALREADY_FINISHED:
      return .alreadyFinished
    case GRPC_CALL_ERROR_TOO_MANY_OPERATIONS:
      return .tooManyOperations
    case GRPC_CALL_ERROR_INVALID_FLAGS:
      return .invalidFlags
    case GRPC_CALL_ERROR_INVALID_METADATA:
      return .invalidMetadata
    case GRPC_CALL_ERROR_INVALID_MESSAGE:
      return .invalidMessage
    case GRPC_CALL_ERROR_NOT_SERVER_COMPLETION_QUEUE:
      return .notServerCompletionQueue
    case GRPC_CALL_ERROR_BATCH_TOO_BIG:
      return .batchTooBig
    case GRPC_CALL_ERROR_PAYLOAD_TYPE_MISMATCH:
      return .payloadTypeMismatch
    default:
      return .unknown
    }
  }
}

public struct CallResult {
  public var statusCode : Int
  public var statusMessage : String?
  public var resultData : Data?
  public var initialMetadata : Metadata?
  public var trailingMetadata : Metadata?
}

public typealias CallCompletion = (CallResult) -> Void
public typealias SendMessageCompletion = (CallError) -> Void

/// A gRPC API call
public class Call {

  /// Pointer to underlying C representation
  private var underlyingCall : UnsafeMutableRawPointer

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
  init(underlyingCall: UnsafeMutableRawPointer, owned: Bool, completionQueue: CompletionQueue) {
    self.underlyingCall = underlyingCall
    self.owned = owned
    self.completionQueue = completionQueue
    self.pendingMessages = []
    self.writing = false
  }

  deinit {
    if (owned) {
      cgrpc_call_destroy(underlyingCall)
    }
  }

  /// Initiate performance of a call without waiting for completion
  ///
  /// - Parameter operations: array of operations to be performed
  /// - Parameter completionQueue: completion queue used to wait for completion
  /// - Returns: the result of initiating the call
  func performOperations(operations: OperationGroup,
                         completionQueue: CompletionQueue)
    -> CallError {
      completionQueue.operationGroups[operations.tag] = operations
      let mutex = CallLock.sharedInstance.mutex
      mutex.lock()
      let error = cgrpc_call_perform(underlyingCall, operations.underlyingOperations, operations.tag)
      mutex.unlock()
      return CallError.callError(grpcCallError:error)
  }

  /// Performs a nonstreaming gRPC API call
  ///
  /// - Parameter message: a ByteBuffer containing the message to send
  /// - Parameter metadata: metadata to send with the call
  /// - Returns: a CallResponse object containing results of the call
  public func performNonStreamingCall(messageData: Data,
                                      metadata: Metadata,
                                      completion: @escaping CallCompletion) -> CallError {

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
                                           operation_receiveMessage],
                               completion:
      {(success) in
        if success {
          completion(CallResult(statusCode:operation_receiveStatusOnClient.status(),
                                statusMessage:operation_receiveStatusOnClient.statusDetails(),
                                resultData:operation_receiveMessage.message()?.data(),
                                initialMetadata:operation_receiveInitialMetadata.metadata(),
                                trailingMetadata:operation_receiveStatusOnClient.metadata()))
        } else {
          completion(CallResult(statusCode:0,
                                statusMessage:nil,
                                resultData:nil,
                                initialMetadata:nil,
                                trailingMetadata:nil))
        }
    })

    return self.perform(operations: group)
  }

  // perform a group of operations (used internally)
  private func perform(operations: OperationGroup) -> CallError {
    return performOperations(operations:operations,
                             completionQueue: self.completionQueue)
  }

  // start a streaming connection
  public func start(metadata: Metadata) -> CallError {
    var error : CallError
    error = self.sendInitialMetadata(metadata: metadata)
    if error != .ok {
      return error
    }
    error = self.receiveInitialMetadata()
    if error != .ok {
      return error
    }
    return self.receiveStatus()
  }

  // send a message over a streaming connection
  public func sendMessage(data: Data,
                          callback:@escaping SendMessageCompletion = {(error) in })
    -> Void {
      DispatchQueue.main.async {
        if self.writing {
          self.pendingMessages.append(data) // TODO: return something if we can't accept another message
          callback(.ok)
        } else {
          self.writing = true
          let error = self.sendWithoutBlocking(data: data)
          callback(error)
        }
      }
  }

  private func sendWithoutBlocking(data: Data) -> CallError {
    let messageBuffer = ByteBuffer(data:data)
    let operation_sendMessage = Operation_SendMessage(message:messageBuffer)
    let operations = OperationGroup(call:self, operations:[operation_sendMessage])
    { (event) in

      // TODO: if the event failed, shut down

      DispatchQueue.main.async {
        if self.pendingMessages.count > 0 {
          let nextMessage = self.pendingMessages.first!
          self.pendingMessages.removeFirst()
          _ = self.sendWithoutBlocking(data: nextMessage)
        } else {
          self.writing = false
        }
      }
    }
    return self.perform(operations:operations)
  }


  // receive a message over a streaming connection
  public func receiveMessage(callback:@escaping ((Data!) -> Void)) -> CallError {
    let operation_receiveMessage = Operation_ReceiveMessage()
    let operations = OperationGroup(call:self, operations:[operation_receiveMessage])
    { (event) in
      if let messageBuffer = operation_receiveMessage.message() {
        callback(messageBuffer.data())
      }
    }
    return self.perform(operations:operations)
  }

  // send initial metadata over a streaming connection
  private func sendInitialMetadata(metadata: Metadata) -> CallError {
    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:metadata);
    let operations = OperationGroup(call:self, operations:[operation_sendInitialMetadata])
    { (success) in
      if (success) {
        print("call successful")
      } else {
        return
      }
    }
    return self.perform(operations:operations)
  }

  // receive initial metadata from a streaming connection
  private func receiveInitialMetadata() -> CallError {
    let operation_receiveInitialMetadata = Operation_ReceiveInitialMetadata()
    let operations = OperationGroup(call:self, operations:[operation_receiveInitialMetadata])
    { (event) in
      let initialMetadata = operation_receiveInitialMetadata.metadata()
      for j in 0..<initialMetadata.count() {
        print("Received initial metadata -> " + initialMetadata.key(index:j) + " : " + initialMetadata.value(index:j))
      }
    }
    return self.perform(operations:operations)
  }

  // receive status from a streaming connection
  private func receiveStatus() -> CallError {
    let operation_receiveStatus = Operation_ReceiveStatusOnClient()
    let operations = OperationGroup(call:self,
                                    operations:[operation_receiveStatus])
    { (event) in
      print("status = \(operation_receiveStatus.status()), \(operation_receiveStatus.statusDetails())")
    }
    return self.perform(operations:operations)
  }

  // close a streaming connection
  public func close(completion:@escaping (() -> Void)) -> CallError {
    let operation_sendCloseFromClient = Operation_SendCloseFromClient()
    let operations = OperationGroup(call:self, operations:[operation_sendCloseFromClient])
    { (event) in
      completion()
    }
    return self.perform(operations:operations)
  }
}
