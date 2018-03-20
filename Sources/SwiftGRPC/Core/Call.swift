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
    try completionQueue.register(operations) {
      Call.callMutex.lock()
      // We need to do the perform *inside* the `completionQueue.register` call, to ensure that the queue can't get
      // shutdown in between registering the operation group and calling `cgrpc_call_perform`.
      let error = cgrpc_call_perform(underlyingCall, operations.underlyingOperations, operations.tag)
      Call.callMutex.unlock()
      if error != GRPC_CALL_OK {
        throw CallError.callError(grpcCallError: error)
      }
    }
  }

  /// Starts a gRPC API call.
  ///
  /// - Parameter style: the style of call to start
  /// - Parameter metadata: metadata to send with the call
  /// - Parameter message: data containing the message to send (.unary and .serverStreaming only)
  /// - Parameter completion: a block to call with call results
  ///     The argument to `completion` will always have `.success = true`
  ///     because operations containing `.receiveCloseOnClient` always succeed.
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
      try perform(OperationGroup(call: self,
                                 operations: [
                                  .sendInitialMetadata(metadata.copy()),
                                  .receiveInitialMetadata
                                  ],
                                 completion: nil))
      try perform(OperationGroup(call: self,
                                 operations: [.receiveStatusOnClient],
                                 completion: completion != nil
                                  ? { op in completion?(CallResult(op)) }
                                  : nil))
      return
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
      messageQueueEmpty.enter()
    }
  }

  /// helper for sending queued messages
  private func sendWithoutBlocking(data: Data, completion: ((Error?) -> Void)?) throws {
    try perform(OperationGroup(
      call: self,
      operations: [.sendMessage(ByteBuffer(data: data))]) { operationGroup in
        // Always enqueue the next message, even if sending this one failed. This ensures that all send completion
        // handlers are called eventually.
        self.sendMutex.synchronize {
          // if there are messages pending, send the next one
          if self.messageQueue.count > 0 {
            let (nextMessage, nextCompletionHandler) = self.messageQueue.removeFirst()
            do {
              try self.sendWithoutBlocking(data: nextMessage, completion: nextCompletionHandler)
            } catch {
              nextCompletionHandler?(error)
            }
          } else {
            // otherwise, we are finished writing
            self.writing = false
          }
        }
        completion?(operationGroup.success ? nil : CallError.unknown)
        self.messageQueueEmpty.leave()
    })
  }

  // Receive a message over a streaming connection.
  /// - Throws: `CallError` if fails to call.
  public func closeAndReceiveMessage(completion: @escaping (CallResult) -> Void) throws {
    try perform(OperationGroup(call: self, operations: [.sendCloseFromClient, .receiveMessage]) { operationGroup in
      completion(CallResult(operationGroup))
    })
  }

  // Receive a message over a streaming connection.
  /// - Throws: `CallError` if fails to call.
  public func receiveMessage(completion: @escaping (CallResult) -> Void) throws {
    try perform(OperationGroup(call: self, operations: [.receiveMessage]) { operationGroup in
      completion(CallResult(operationGroup))
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
