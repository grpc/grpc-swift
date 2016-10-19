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
import Foundation // for String.Encoding

public protocol Session {
  func run() -> Void
}

/// A gRPC request handler
public class Handler {
  /// Pointer to underlying C representation
  private var underlyingHandler: UnsafeMutableRawPointer

  /// Completion queue for handler response operations
  internal var completionQueue: CompletionQueue

  /// Metadata received with the request
  public var requestMetadata: Metadata

  /// runnable object that we want retained until the handler is destroyed
  public var session : Session!

  /// A Call object that can be used to respond to the request
  internal lazy var call: Call = {
    return Call(underlyingCall: cgrpc_handler_get_call(self.underlyingHandler),
                owned: false,
                completionQueue: self.completionQueue)
  }()

  /// The host name sent with the request
  public lazy var host: String = {
    return String(cString:cgrpc_handler_host(self.underlyingHandler),
                  encoding:.utf8)!;
  }()

  /// The method name sent with the request
  public lazy var method: String = {
    return String(cString:cgrpc_handler_method(self.underlyingHandler),
                  encoding:.utf8)!;
  }()

  /// The caller address associated with the request
  public lazy var caller: String = {
    return String(cString:cgrpc_handler_call_peer(self.underlyingHandler),
                  encoding:.utf8)!;
  }()

  /// Initializes a Handler
  ///
  /// - Parameter underlyingServer: the underlying C representation of the associated server
  init(underlyingServer:UnsafeMutableRawPointer) {
    underlyingHandler = cgrpc_handler_create_with_server(underlyingServer)
    requestMetadata = Metadata()
    completionQueue = CompletionQueue(
      underlyingCompletionQueue:cgrpc_handler_get_completion_queue(underlyingHandler))
    completionQueue.name = "Handler"
  }

  deinit {
    cgrpc_handler_destroy(self.underlyingHandler)
  }

  /// Requests a call for the handler
  ///
  /// Fills the handler properties with information about the received request
  ///
  func requestCall(tag: Int) throws -> Void {
    let error = cgrpc_handler_request_call(underlyingHandler, requestMetadata.underlyingArray, tag)
    if error != GRPC_CALL_OK {
      throw CallError.callError(grpcCallError: error)
    }
  }

  /// Receive the message sent with a call
  ///
  public func receiveMessage(initialMetadata: Metadata,
                             completion:@escaping ((Data?) throws -> Void)) throws -> Void {
    let operations = OperationGroup(
      call:call,
      operations:[
        .sendInitialMetadata(initialMetadata),
        .receiveMessage])
    {(operationGroup) in
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
  /// - Parameter trailingMetadata: trailing metadata to send
  public func sendResponse(message: Data,
                           statusCode: Int,
                           statusMessage: String,
                           trailingMetadata: Metadata) throws -> Void {
    let messageBuffer = ByteBuffer(data:message)
    let operations = OperationGroup(
      call:call,
      operations:[
        .receiveCloseOnServer,
        .sendStatusFromServer(statusCode, statusMessage, trailingMetadata),
        .sendMessage(messageBuffer)])
    {(operationGroup) in
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
                           completion:@escaping (() throws -> Void)) throws -> Void {
    let operations = OperationGroup(call:call,
                                    operations:[.sendInitialMetadata(initialMetadata)])
    {(operationGroup) in
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
  public func receiveMessage(completion:(@escaping (Data?) throws -> Void)) throws -> Void {
    let operations = OperationGroup(call:call, operations:[.receiveMessage])
    {(operationGroup) in
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
                           completion: @escaping () throws -> Void) throws -> Void {
    let operations = OperationGroup(call:call,
                                    operations:[.sendMessage(ByteBuffer(data:message))])
    {(operationGroup) in
      if operationGroup.success {
        try completion()
      }
    }
    try call.perform(operations)
  }

  /// Recognize when the client has closed a request
  ///
  /// - Parameter completion: a completion handler to call after request has been closed
  public func receiveClose(completion: @escaping () throws -> Void) throws -> Void {
    let operations = OperationGroup(call:call,
                                    operations:[.receiveCloseOnServer])
    {(operationGroup) in
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
  public func sendStatus(statusCode: Int,
                         statusMessage: String,
                         trailingMetadata: Metadata,
                         completion:@escaping (() -> Void)) throws -> Void {
    let operations = OperationGroup(call:call,
                                    operations:[.sendStatusFromServer(statusCode,
                                                                      statusMessage,
                                                                      trailingMetadata)])
    {(operationGroup) in
      if operationGroup.success {
        completion()
      }
    }
    try call.perform(operations)
  }
}
