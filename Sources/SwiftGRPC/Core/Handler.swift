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
  fileprivate let underlyingHandler: UnsafeMutableRawPointer

  /// Completion queue for handler response operations
  let completionQueue: CompletionQueue

  /// Metadata received with the request
  public let requestMetadata: Metadata

  /// A Call object that can be used to respond to the request
  public private(set) lazy var call: Call = {
    Call(underlyingCall: cgrpc_handler_get_call(self.underlyingHandler),
         owned: true,
         completionQueue: self.completionQueue)
  }()

  /// The host name sent with the request
  public lazy var host: String? = {
    // We actually know that this method will never return nil,
    // so we can forcibly unwrap the result. (Also below.)
    let string = cgrpc_handler_copy_host(self.underlyingHandler)!
    defer { cgrpc_free_copied_string(string) }
    return String(cString: string, encoding: .utf8)
  }()

  /// The method name sent with the request
  public lazy var method: String? = {
    let string = cgrpc_handler_copy_method(self.underlyingHandler)!
    defer { cgrpc_free_copied_string(string) }
    return String(cString: string, encoding: .utf8)
  }()

  /// The caller address associated with the request
  public lazy var caller: String? = {
    let string = cgrpc_handler_call_peer(self.underlyingHandler)!
    defer { cgrpc_free_copied_string(string) }
    return String(cString: string, encoding: .utf8)
  }()

  /// Initializes a Handler
  ///
  /// - Parameter underlyingServer: the underlying C representation of the associated server
  init(underlyingServer: UnsafeMutableRawPointer) {
    underlyingHandler = cgrpc_handler_create_with_server(underlyingServer)
    requestMetadata = Metadata()
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_handler_get_completion_queue(underlyingHandler), name: "Handler")
  }

  deinit {
    // Technically unnecessary, because the handler only gets released once the completion queue has already been
    // shut down, but it doesn't hurt to keep this here.
    completionQueue.shutdown()
    cgrpc_handler_destroy(self.underlyingHandler)
  }

  /// Requests a call for the handler
  ///
  /// Fills the handler properties with information about the received request
  ///
  func requestCall(tag: Int) throws {
    let error = cgrpc_handler_request_call(underlyingHandler, requestMetadata.underlyingArray, UnsafeMutableRawPointer(bitPattern: tag))
    if error != GRPC_CALL_OK {
      throw CallError.callError(grpcCallError: error)
    }
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
                           completion: ((Bool) -> Void)? = nil) throws {
    try call.perform(OperationGroup(
      call: call,
      operations: [.sendInitialMetadata(initialMetadata)],
      completion: completion != nil
        ? { operationGroup in completion?(operationGroup.success) }
        : nil))
  }

  /// Receive the message sent with a call
  ///
  public func receiveMessage(initialMetadata: Metadata,
                             completion: @escaping (Data?) -> Void) throws {
    try call.perform(OperationGroup(
      call: call,
      operations: [
        .sendInitialMetadata(initialMetadata),
        .receiveMessage
    ]) { operationGroup in
      if operationGroup.success {
        completion(operationGroup.receivedMessage()?.data())
      } else {
        completion(nil)
      }
    })
  }

  /// Sends the response to a request.
  /// The completion handler does not take an argument because operations containing `.receiveCloseOnServer` always succeed.
  public func sendResponse(message: Data, status: ServerStatus,
                           completion: (() -> Void)? = nil) throws {
    let messageBuffer = ByteBuffer(data: message)
    try call.perform(OperationGroup(
      call: call,
      operations: [
        .sendMessage(messageBuffer),
        .receiveCloseOnServer,
        .sendStatusFromServer(status.code, status.message, status.trailingMetadata)
    ]) { _ in
      completion?()
      self.shutdown()
    })
  }

  /// Send final status to the client.
  /// The completion handler does not take an argument because operations containing `.receiveCloseOnServer` always succeed.
  public func sendStatus(_ status: ServerStatus, completion: (() -> Void)? = nil) throws {
    try call.perform(OperationGroup(
      call: call,
      operations: [
        .receiveCloseOnServer,
        .sendStatusFromServer(status.code, status.message, status.trailingMetadata)
    ]) { _ in
      completion?()
      self.shutdown()
    })
  }
}
