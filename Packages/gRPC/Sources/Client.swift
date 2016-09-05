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

/// A gRPC Client
public class Client {

  /// Pointer to underlying C representation
  var c: UnsafeMutableRawPointer!

  /// Completion queue for client call operations
  public var completionQueue: CompletionQueue

  /// Initializes a gRPC client
  ///
  /// - Parameter address: the address of the server to be called
  public init(address: String) {
    c = cgrpc_client_create(address)
    completionQueue = CompletionQueue(cq:cgrpc_client_completion_queue(c))
  }

  deinit {
    cgrpc_client_destroy(c)
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter host: the gRPC host name for the call
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to make the request
  public func createCall(host:String, method:String, timeout:Double) -> Call {
    let call = cgrpc_client_create_call(c, method, host, timeout)!
    return Call(call:call, owned:true)
  }

  /// Performs a nonstreaming gRPC API call
  ///
  /// - Parameter host: the gRPC host name for the call
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter message: a ByteBuffer containing the message to send
  /// - Parameter metadata: metadata to send with the call
  /// - Returns: a CallResponse object containing results of the call
  public func performRequest(host: String,
                             method: String,
                             message: ByteBuffer,
                             metadata: Metadata,
                             completion: ((CallResponse) -> Void)) -> Call   {
    let call = createCall(host:host, method:method, timeout:600.0)

    let operation_sendInitialMetadata = Operation_SendInitialMetadata(metadata:metadata);
    let operation_sendMessage = Operation_SendMessage(message:message)
    let operation_sendCloseFromClient = Operation_SendCloseFromClient()
    let operation_receiveInitialMetadata = Operation_ReceiveInitialMetadata()
    let operation_receiveStatusOnClient = Operation_ReceiveStatusOnClient()
    let operation_receiveMessage = Operation_ReceiveMessage()

    let group = OperationGroup(call:call,
                               operations:[operation_sendInitialMetadata,
                                           operation_sendMessage,
                                           operation_sendCloseFromClient,
                                           operation_receiveInitialMetadata,
                                           operation_receiveStatusOnClient,
                                           operation_receiveMessage])
    { (event) in
      if (event.type == GRPC_OP_COMPLETE) {
        let response = CallResponse(status:operation_receiveStatusOnClient.status(),
                                    statusDetails:operation_receiveStatusOnClient.statusDetails(),
                                    message:operation_receiveMessage.message(),
                                    initialMetadata:operation_receiveInitialMetadata.metadata(),
                                    trailingMetadata:operation_receiveStatusOnClient.metadata())
        completion(response)
      } else {
        completion(CallResponse(completion: event.type))
      }
    }
    let call_error = self.perform(call: call, operations: group)
    print ("call error = \(call_error)")
    print("calling \(completionQueue.cq)")
    return call
  }

  public func perform(call: Call, operations: OperationGroup) -> grpc_call_error {
    self.completionQueue.operationGroups[operations.tag] = operations
    return call.performOperations(operations:operations,
                                  tag:operations.tag,
                                  completionQueue: self.completionQueue)
  }
}
