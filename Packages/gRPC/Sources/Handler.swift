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

/// A gRPC request handler
public class Handler {
  /// Pointer to underlying C representation
  private var underlyingHandler: UnsafeMutableRawPointer

  /// Completion queue for handler response operations
  var completionQueue: CompletionQueue

  /// Metadata received with the request
  public var requestMetadata: Metadata

  /// A Call object that can be used to respond to the request
  lazy var call: Call = {
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
  /// - Parameter h: the underlying C representation
  init(underlyingHandler:UnsafeMutableRawPointer) {
    self.underlyingHandler = underlyingHandler;
    self.requestMetadata = Metadata()
    self.completionQueue = CompletionQueue(
      underlyingCompletionQueue:cgrpc_handler_get_completion_queue(underlyingHandler))
    self.completionQueue.name = "Handler"
  }

  deinit {
    cgrpc_handler_destroy(self.underlyingHandler)
  }

  /// Requests a call for the handler
  ///
  /// Fills the handler properties with information about the received request
  ///
  /// - Returns: a CallError indicating the result of requesting the call
  func requestCall(tag: Int) -> CallError {
    let error = cgrpc_handler_request_call(underlyingHandler, requestMetadata.underlyingArray, tag)
    return CallError.callError(grpcCallError: error)
  }

  /// Receive the message sent with a call
  ///
  /// - Returns: a tuple containing status codes and a message (if available)
  public func receiveMessage(initialMetadata: Metadata,
                             completion:@escaping ((Data?) -> Void)) -> Void {
    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:initialMetadata);
    let operation_receiveMessage = Operation_ReceiveMessage()
    let operations = OperationGroup(
      call:call,
      operations:[
        operation_sendInitialMetadata,
        operation_receiveMessage])
    {(success) in
      if (success) {
        completion(operation_receiveMessage.message()!.data())
      } else {
        completion(nil)
      }
    }
    _ = call.performOperations(operations:operations,
                               completionQueue: self.completionQueue)
  }

  /// Sends the response to a request
  ///
  /// - Parameter message: the message to send
  /// - Returns: a tuple containing status codes
  public func sendResponse(message: Data,
                           trailingMetadata: Metadata) -> Void {
    let operation_receiveCloseOnServer = Operation_ReceiveCloseOnServer();
    let operation_sendStatusFromServer = Operation_SendStatusFromServer(status:0,
                                                                        statusDetails:"OK",
                                                                        metadata:trailingMetadata)
    let messageBuffer = ByteBuffer(data:message)
    let operation_sendMessage = Operation_SendMessage(message:messageBuffer)
    let operations = OperationGroup(
      call:call,
      operations:[
        operation_receiveCloseOnServer,
        operation_sendStatusFromServer,
        operation_sendMessage])
    {(call_error) in
      self.shutdown()
    }
    _ = call.performOperations(operations:operations,
                               completionQueue: self.completionQueue)
  }

  /// shutdown the handler's completion queue
  public func shutdown() {
    completionQueue.shutdown()
  }

  /// Send initial metadata in response to a connection
  public func sendMetadata(initialMetadata: Metadata,
                           completion:@escaping (() -> Void)) {
    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:initialMetadata);
    let operations = OperationGroup(call:call, operations:[operation_sendInitialMetadata])
    {(success) in
      if (success) {
        completion()
      } else {
        completion()
      }
    }
    _ = call.performOperations(operations:operations,
                               completionQueue: self.completionQueue)
  }

  /// Receive the message sent with a call
  ///
  /// - Returns: a tuple containing status codes and a message (if available)
  public func receiveMessage(completion:(@escaping (Data?) -> Void)) -> Void {
    let operation_receiveMessage = Operation_ReceiveMessage()
    let operations = OperationGroup(call:call, operations:[operation_receiveMessage])
    {(success) in
      if (success) {
        print("server receiveMessage complete")
        if let message = operation_receiveMessage.message() {
          completion(message.data())
        } else {
          completion(nil)
        }
      } else {
        completion(nil)
      }
    }

    let call_error = call.performOperations(operations:operations,
                                            completionQueue: self.completionQueue)
    print("perform receiveMessage \(call_error)")
  }

  /// Sends the response to a request
  ///
  /// - Parameter message: the message to send
  /// - Returns: a tuple containing status codes
  public func sendResponse(message: Data,
                           completion: @escaping () -> Void) -> Void {
    let operation_sendMessage = Operation_SendMessage(message:ByteBuffer(data:message))
    let operations = OperationGroup(call:call, operations:[operation_sendMessage])
    {(event) in
      print("server sendResponse complete")
      completion()
    }
    _ = call.performOperations(operations:operations,
                               completionQueue: self.completionQueue)
  }

  /// Recognize when the client has closed a request
  public func receiveClose(completion: @escaping () -> Void) -> Void {
    let operation_receiveClose = Operation_ReceiveCloseOnServer()
    let operations = OperationGroup(call:call, operations:[operation_receiveClose])
    {(event) in
      print("server receiveClose complete")
      completion()
    }
    let call_error = call.performOperations(operations:operations,
                                            completionQueue: self.completionQueue)
    print("perform receiveClose \(call_error)")
  }

  /// Send final status to the client
  public func sendStatus(trailingMetadata: Metadata,
                         completion:@escaping (() -> Void)) -> Void {
    let operation_sendStatusFromServer = Operation_SendStatusFromServer(status:0,
                                                                        statusDetails:"OK",
                                                                        metadata:trailingMetadata)
    let operations = OperationGroup(call:call, operations:[operation_sendStatusFromServer])
    {(event) in
      print("server sendStatus complete")
      completion()
    }
    _ = call.performOperations(operations:operations,
                               completionQueue: self.completionQueue)
  }
}
