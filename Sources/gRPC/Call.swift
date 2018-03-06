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

public enum CallStyle {
  case unary
  case serverStreaming
  case clientStreaming
  case bidiStreaming
}

public enum CallWarning: Error {
  case blocked
}

public enum CallError: Error {
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
    switch error {
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

public struct CallResult: CustomStringConvertible {
  public let statusCode: StatusCode
  public let statusMessage: String?
  public let resultData: Data?
  public let initialMetadata: Metadata?
  public let trailingMetadata: Metadata?

  fileprivate init(_ op: OperationGroup) {
    if op.success {
      if let statusCodeRawValue = op.receivedStatusCode() {
        if let statusCode = StatusCode(rawValue: statusCodeRawValue) {
          self.statusCode = statusCode
        } else {
          statusCode = .unknown
        }
      } else {
        statusCode = .ok
      }
      statusMessage = op.receivedStatusMessage()
      resultData = op.receivedMessage()?.data()
      initialMetadata = op.receivedInitialMetadata()
      trailingMetadata = op.receivedTrailingMetadata()
    } else {
      statusCode = .ok
      statusMessage = nil
      resultData = nil
      initialMetadata = nil
      trailingMetadata = nil
    }
  }

  public var description: String {
    var result = "status \(statusCode)"
    if let statusMessage = self.statusMessage {
      result += ": " + statusMessage
    }
    if let resultData = self.resultData {
      result += "\n"
      result += resultData.description
    }
    if let initialMetadata = self.initialMetadata {
      result += "\n"
      result += initialMetadata.description
    }
    if let trailingMetadata = self.trailingMetadata {
      result += "\n"
      result += trailingMetadata.description
    }
    return result
  }
}

/// A gRPC API call
public class Call {
  /// Shared mutex for synchronizing calls to cgrpc_call_perform()
  private static let callMutex = Mutex()

  /// Maximum number of messages that can be queued
  public static var messageQueueMaxLength: Int? = nil

  /// Pointer to underlying C representation
  private let underlyingCall: UnsafeMutableRawPointer

  /// Completion queue used for call
  private let completionQueue: CompletionQueue

  /// True if this instance is responsible for deleting the underlying C representation
  private let owned: Bool

  /// A queue of pending messages to send over the call
  private var messageQueue: [(dataToSend: Data, completion: ((Error?) -> Void)?)] = []

  /// A dispatch group that contains all pending send operations.
  /// You can wait on it to ensure that all currently enqueued messages have been sent.
  public let messageQueueEmpty = DispatchGroup()
  
  /// True if a message write operation is underway
  private var writing: Bool

  /// Mutex for synchronizing message sending
  private let sendMutex: Mutex

  /// Dispatch queue used for sending messages asynchronously
  private let messageDispatchQueue: DispatchQueue = DispatchQueue.global()

  /// Initializes a Call representation
  ///
  /// - Parameter call: the underlying C representation
  /// - Parameter owned: true if this instance is responsible for deleting the underlying call
  init(underlyingCall: UnsafeMutableRawPointer, owned: Bool, completionQueue: CompletionQueue) {
    self.underlyingCall = underlyingCall
    self.owned = owned
    self.completionQueue = completionQueue
    writing = false
    sendMutex = Mutex()
  }

  deinit {
    if owned {
      cgrpc_call_destroy(underlyingCall)
    }
  }

  /// Initiates performance of a group of operations without waiting for completion.
  ///
  /// - Parameter operations: group of operations to be performed
  /// - Returns: the result of initiating the call
  /// - Throws: `CallError` if fails to call.
  func perform(_ operations: OperationGroup) throws {
    completionQueue.register(operations)
    Call.callMutex.lock()
    let error = cgrpc_call_perform(underlyingCall, operations.underlyingOperations, operations.tag)
    Call.callMutex.unlock()
    if error != GRPC_CALL_OK {
      throw CallError.callError(grpcCallError: error)
    }
  }

  /// Starts a gRPC API call.
  ///
  /// - Parameter style: the style of call to start
  /// - Parameter metadata: metadata to send with the call
  /// - Parameter message: data containing the message to send (.unary and .serverStreaming only)
  /// - Parameter completion: a block to call with call results
  /// - Throws: `CallError` if fails to call.
  public func start(_ style: CallStyle,
                    metadata: Metadata,
                    message: Data? = nil,
                    completion: ((CallResult) -> Void)? = nil) throws {
    var operations: [Operation] = []
    switch style {
    case .unary:
      guard let message = message else {
        throw CallError.invalidMessage
      }
      operations = [
        .sendInitialMetadata(metadata.copy()),
        .sendMessage(ByteBuffer(data:message)),
        .sendCloseFromClient,
        .receiveInitialMetadata,
        .receiveMessage,
        .receiveStatusOnClient,
      ]
    case .serverStreaming:
      guard let message = message else {
        throw CallError.invalidMessage
      }
      operations = [
        .sendInitialMetadata(metadata.copy()),
        .sendMessage(ByteBuffer(data:message)),
        .sendCloseFromClient,
        .receiveInitialMetadata,
        .receiveStatusOnClient,
      ]
    case .clientStreaming, .bidiStreaming:
      operations = [
        .sendInitialMetadata(metadata.copy()),
        .receiveInitialMetadata,
        .receiveStatusOnClient,
      ]
    }
    try perform(OperationGroup(call: self,
                               operations: operations,
                               completion: completion != nil
                                ? { op in completion?(CallResult(op)) }
                                : nil))
  }

  /// Sends a message over a streaming connection.
  ///
  /// Parameter data: the message data to send
  /// - Throws: `CallError` if fails to call. `CallWarning` if blocked.
  public func sendMessage(data: Data, completion: ((Error?) -> Void)? = nil) throws {
    messageQueueEmpty.enter()
    try sendMutex.synchronize {
      if writing {
        if let messageQueueMaxLength = Call.messageQueueMaxLength,
          messageQueue.count >= messageQueueMaxLength {
          throw CallWarning.blocked
        }
        messageQueue.append((dataToSend: data, completion: completion))
      } else {
        writing = true
        try sendWithoutBlocking(data: data, completion: completion)
      }  
    }
  }

  /// helper for sending queued messages
  private func sendWithoutBlocking(data: Data, completion: ((Error?) -> Void)?) throws {
    try perform(OperationGroup(call: self,
                               operations: [.sendMessage(ByteBuffer(data: data))]) { operationGroup in
        // TODO(timburks, danielalm): Is the `async` dispatch here needed, and/or should we call the completion handler
        // and leave `messageQueueEmpty` in the `async` block as well?
        self.messageDispatchQueue.async {
          // Always enqueue the next message, even if sending this one failed. This ensures that all send completion
          // handlers are called eventually.
          self.sendMutex.synchronize {
            // if there are messages pending, send the next one
            if self.messageQueue.count > 0 {
              let (nextMessage, nextCompletionHandler) = self.messageQueue.removeFirst()
              do {
                try self.sendWithoutBlocking(data: nextMessage, completion: nextCompletionHandler)
              } catch (let callError) {
                nextCompletionHandler?(callError)
              }
            } else {
              // otherwise, we are finished writing
              self.writing = false
            }
          }
        }
        completion?(operationGroup.success ? nil : CallError.unknown)
        self.messageQueueEmpty.leave()
    })
  }

  // Receive a message over a streaming connection.
  /// - Throws: `CallError` if fails to call.
  public func closeAndReceiveMessage(completion: @escaping (Data?) throws -> Void) throws {
    try perform(OperationGroup(call: self, operations: [.sendCloseFromClient, .receiveMessage]) { operationGroup in
      if operationGroup.success {
        if let messageBuffer = operationGroup.receivedMessage() {
          try completion(messageBuffer.data())
        } else {
          try completion(nil) // an empty response signals the end of a connection
        }
      }
    })
  }

  // Receive a message over a streaming connection.
  /// - Throws: `CallError` if fails to call.
  public func receiveMessage(completion: @escaping (Data?) throws -> Void) throws {
    try perform(OperationGroup(call: self, operations: [.receiveMessage]) { operationGroup in
      if operationGroup.success {
        try completion(operationGroup.receivedMessage()?.data())
      } else {
        try completion(nil)
      }
    })
  }

  // Closes a streaming connection.
  /// - Throws: `CallError` if fails to call.
  public func close(completion: (() -> Void)? = nil) throws {
    try perform(OperationGroup(call: self, operations: [.sendCloseFromClient],
                               completion: completion != nil
                                ? { op in completion?() }
                                : nil))
  }

  // Get the current message queue length
  public func messageQueueLength() -> Int {
    return messageQueue.count
  }

  /// Finishes the request side of this call, notifies the server that the RPC should be cancelled,
  /// and finishes the response side of the call with an error of code CANCELED.
  public func cancel() {
    Call.callMutex.synchronize {
      cgrpc_call_cancel(underlyingCall)
    }
  }
}
