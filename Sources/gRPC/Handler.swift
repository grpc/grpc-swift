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
import Foundation // for String.Encoding

/// A gRPC request handler
public class Handler {
  /// Pointer to underlying C representation
  private var underlyingHandler: UnsafeMutableRawPointer
  
  /// Completion queue for handler response operations
  internal var completionQueue: CompletionQueue
  
  /// Metadata received with the request
  public var requestMetadata: Metadata
  
  /// A Call object that can be used to respond to the request
  internal lazy var call: Call = {
    Call(underlyingCall: cgrpc_handler_get_call(self.underlyingHandler),
         owned: false,
         completionQueue: self.completionQueue)
  }()
  
  /// The host name sent with the request
  public lazy var host: String = {
    if let string = cgrpc_handler_copy_host(self.underlyingHandler) {
      defer {
        cgrpc_free_copied_string(string)
      }
      return String(cString: string, encoding: .utf8)!
    } else {
      return ""
    }
  }()
  
  /// The method name sent with the request
  public lazy var method: String = {
    if let string = cgrpc_handler_copy_method(self.underlyingHandler) {
      defer {
        cgrpc_free_copied_string(string)
      }
      return String(cString: string, encoding: .utf8)!
    } else {
      return ""
    }
  }()
  
  /// The caller address associated with the request
  public lazy var caller: String = {
    String(cString: cgrpc_handler_call_peer(self.underlyingHandler),
           encoding: .utf8)!
  }()
  
  /// Initializes a Handler
  ///
  /// - Parameter underlyingServer: the underlying C representation of the associated server
  init(underlyingServer: UnsafeMutableRawPointer) {
    underlyingHandler = cgrpc_handler_create_with_server(underlyingServer)
    requestMetadata = Metadata()
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_handler_get_completion_queue(underlyingHandler))
    completionQueue.name = "Handler"
  }
  
  deinit {
    cgrpc_handler_destroy(self.underlyingHandler)
  }
  
  /// Requests a call for the handler
  ///
  /// Fills the handler properties with information about the received request
  ///
  func requestCall(tag: Int) throws {
    let error = cgrpc_handler_request_call(underlyingHandler, requestMetadata.underlyingArray, tag)
    if error != GRPC_CALL_OK {
      throw CallError.callError(grpcCallError: error)
    }
  }
  
  /// Receive the message sent with a call
  ///
  public func receiveMessage(initialMetadata: Metadata,
                             completion: @escaping ((Data?) throws -> Void)) throws {
    let operations = OperationGroup(call: call,
                                    operations: [
                                      .sendInitialMetadata(initialMetadata),
                                      .receiveMessage
    ]) { operationGroup in
      if operationGroup.success {
        try completion(operationGroup.receivedMessage()?.data())
      } else {
        try completion(nil)
      }
    }
    try call.perform(operations)
  }
  
  /// Sends the response to a request
  ///
  /// - Parameter message: the message to send
  /// - Parameter statusCode: status code to send
  /// - Parameter statusMessage: status message to send
  /// - Parameter trailingMetadata: trailing metadata to send
  public func sendResponse(message: Data,
                           statusCode: StatusCode,
                           statusMessage: String,
                           trailingMetadata: Metadata) throws {
    let messageBuffer = ByteBuffer(data: message)
    let operations = OperationGroup(call: call,
                                    operations: [
                                      .receiveCloseOnServer,
                                      .sendStatusFromServer(statusCode, statusMessage, trailingMetadata),
                                      .sendMessage(messageBuffer)
    ]) { operationGroup in
      if operationGroup.success {
        self.shutdown()
      }
    }
    try call.perform(operations)
  }
  
  /// Sends the response to a request
  ///
  /// - Parameter statusCode: status code to send
  /// - Parameter statusMessage: status message to send
  /// - Parameter trailingMetadata: trailing metadata to send
  public func sendResponse(statusCode: StatusCode,
                           statusMessage: String,
                           trailingMetadata: Metadata) throws {
    let operations = OperationGroup(call: call,
                                    operations: [
                                      .receiveCloseOnServer,
                                      .sendStatusFromServer(statusCode, statusMessage, trailingMetadata)
    ]) { operationGroup in
      if operationGroup.success {
        self.shutdown()
      }
    }
    try call.perform(operations)
  }
  
  /// Shuts down the handler's completion queue
  public func shutdown() {
    completionQueue.shutdown()
  }
  
  /// Send initial metadata in response to a connection
  ///
  /// - Parameter initialMetadata: initial metadata to send
  /// - Parameter completion: a completion handler to call after the metadata has been sent
  public func sendMetadata(initialMetadata: Metadata,
                           completion: @escaping (() throws -> Void)) throws {
    let operations = OperationGroup(call: call,
                                    operations: [.sendInitialMetadata(initialMetadata)]) { operationGroup in
      if operationGroup.success {
        try completion()
      } else {
        try completion()
      }
    }
    try call.perform(operations)
  }
  
  /// Receive the message sent with a call
  ///
  /// - Parameter completion: a completion handler to call after the message has been received
  /// - Returns: a tuple containing status codes and a message (if available)
  public func receiveMessage(completion: (@escaping (Data?) throws -> Void)) throws {
    let operations = OperationGroup(call: call, operations: [.receiveMessage]) { operationGroup in
      if operationGroup.success {
        if let message = operationGroup.receivedMessage() {
          try completion(message.data())
        } else {
          try completion(nil)
        }
      } else {
        try completion(nil)
      }
    }
    try call.perform(operations)
  }
  
  /// Sends the response to a request
  ///
  /// - Parameter message: the message to send
  /// - Parameter completion: a completion handler to call after the response has been sent
  public func sendResponse(message: Data,
                           completion: @escaping () throws -> Void) throws {
    let operations = OperationGroup(call: call,
                                    operations: [.sendMessage(ByteBuffer(data: message))]) { operationGroup in
      if operationGroup.success {
        try completion()
      }
    }
    try call.perform(operations)
  }
  
  /// Recognize when the client has closed a request
  ///
  /// - Parameter completion: a completion handler to call after request has been closed
  public func receiveClose(completion: @escaping () throws -> Void) throws {
    let operations = OperationGroup(call: call,
                                    operations: [.receiveCloseOnServer]) { operationGroup in
      if operationGroup.success {
        try completion()
      }
    }
    try call.perform(operations)
  }
  
  /// Send final status to the client
  ///
  /// - Parameter statusCode: status code to send
  /// - Parameter statusMessage: status message to send
  /// - Parameter trailingMetadata: trailing metadata to send
  /// - Parameter completion: a completion handler to call after the status has been sent
  public func sendStatus(statusCode: StatusCode,
                         statusMessage: String,
                         trailingMetadata: Metadata,
                         completion: @escaping (() -> Void)) throws {
    let operations = OperationGroup(call: call,
                                    operations: [
                                      .sendStatusFromServer(statusCode,
                                                            statusMessage,
                                                            trailingMetadata)
    ]) { operationGroup in
      if operationGroup.success {
        completion()
      }
    }
    try call.perform(operations)
  }
}
