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

public enum CallStyle {
  case unary
  case serverStreaming
  case clientStreaming
  case bidiStreaming
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

  fileprivate init(_ op : OperationGroup) {
    if (op.success) {
      self.statusCode = op.receivedStatusCode()!
      self.statusMessage = op.receivedStatusMessage()
      self.resultData = op.receivedMessage()?.data()
      self.initialMetadata = op.receivedInitialMetadata()
      self.trailingMetadata = op.receivedTrailingMetadata()
    } else {
      self.statusCode = 0
      self.statusMessage = nil
      self.resultData = nil
      self.initialMetadata = nil
      self.trailingMetadata = nil
    }
  }
}

/// A gRPC API call
public class Call {

  /// Shared mutex for synchronizing calls to cgrpc_call_perform()
  private static let callMutex = Mutex()

  /// Maximum number of messages that can be queued
  private static var maximumQueuedMessages = 10

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

  /// Mutex for synchronizing message sending
  private var sendMutex : Mutex

  /// Dispatch queue used for sending messages asynchronously
  private var messageDispatchQueue: DispatchQueue = DispatchQueue.global()

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
    self.sendMutex = Mutex()
  }

  deinit {
    if (owned) {
      cgrpc_call_destroy(underlyingCall)
    }
  }

  /// Initiates performance of a group of operations without waiting for completion.
  ///
  /// - Parameter operations: group of operations to be performed
  /// - Returns: the result of initiating the call
  internal func perform(_ operations: OperationGroup) throws -> Void {
    completionQueue.register(operations)
    Call.callMutex.lock()
    let error = cgrpc_call_perform(underlyingCall, operations.underlyingOperations, operations.tag)
    Call.callMutex.unlock()
    if error != GRPC_CALL_OK {
      throw CallError.callError(grpcCallError:error)
    }
  }

  /// Starts a gRPC API call.
  ///
  /// - Parameter style: the style of call to start
  /// - Parameter metadata: metadata to send with the call
  /// - Parameter message: data containing the message to send (.unary and .serverStreaming only)
  /// - Parameter callback: a block to call with call results
  public func start(_ style: CallStyle,
                    metadata: Metadata,
                    message: Data? = nil,
                    completion: @escaping (CallResult) -> Void)
    throws -> Void {
      var operations : [Operation] = []
      switch style {
      case .unary:
        guard let message = message else {
          throw CallError.invalidMessage
        }
        operations = [.sendInitialMetadata(metadata.copy() as! Metadata),
                      .receiveInitialMetadata,
                      .receiveStatusOnClient,
                      .sendMessage(ByteBuffer(data:message)),
                      .sendCloseFromClient,
                      .receiveMessage]
      case .serverStreaming:
        guard let message = message else {
          throw CallError.invalidMessage
        }
        operations = [.sendInitialMetadata(metadata.copy() as! Metadata),
                      .receiveInitialMetadata,
                      .receiveStatusOnClient,
                      .sendMessage(ByteBuffer(data:message)),
                      .sendCloseFromClient]
      case .clientStreaming, .bidiStreaming:
        operations = [.sendInitialMetadata(metadata.copy() as! Metadata),
                      .receiveInitialMetadata,
                      .receiveStatusOnClient]
      }
      try self.perform(OperationGroup(call:self,
                                      operations:operations,
                                      completion:{(op) in completion(CallResult(op))}))
  }

  /// Sends a message over a streaming connection.
  ///
  /// Parameter data: the message data to send
  /// Returns: true if the message could be queued or sent, false if the queue is full
  public func sendMessage(data: Data) -> Bool {
    self.sendMutex.lock()
    defer {self.sendMutex.unlock()}
    if self.writing {
      if self.pendingMessages.count == Call.maximumQueuedMessages {
        return false
      }
      self.pendingMessages.append(data) // TODO: return something if we can't accept another message
    } else {
      self.writing = true
      do {
        try self.sendWithoutBlocking(data: data)
      } catch (let callError) {
        print("Call sendMessage: grpc error \(callError)")
      }
    }
    return true
  }

  /// helper for sending queued messages
  private func sendWithoutBlocking(data: Data) throws -> Void {
    try self.perform(OperationGroup(call:self,
                                    operations:[.sendMessage(ByteBuffer(data:data))])
    {(operationGroup) in
      if operationGroup.success {
        self.messageDispatchQueue.async {
          self.sendMutex.synchronize {
            // if there are messages pending, send the next one
            if self.pendingMessages.count > 0 {
              let nextMessage = self.pendingMessages.first!
              self.pendingMessages.removeFirst()
              do {
                try self.sendWithoutBlocking(data: nextMessage)
              } catch (let callError) {
                print("Call sendWithoutBlocking: grpc error \(callError)")
              }
            } else {
              // otherwise, we are finished writing
              self.writing = false
            }
          }
        }
      } else {
        // TODO: if the event failed, shut down
      }
    })
  }

  // Receive a message over a streaming connection.
  public func receiveMessage(callback:@escaping ((Data!) throws -> Void)) throws -> Void {
    try self.perform(OperationGroup(call:self, operations:[.receiveMessage])
    {(operationGroup) in
      if operationGroup.success {
        if let messageBuffer = operationGroup.receivedMessage() {
          try callback(messageBuffer.data())
        } else {
          try callback(nil) // an empty response signals the end of a connection
        }
      }
    })
  }

  // Closes a streaming connection.
  public func close(completion:@escaping (() -> Void)) throws -> Void {
    try self.perform(OperationGroup(call:self, operations:[.sendCloseFromClient])
    {(operationGroup) in completion()
    })
  }
}
