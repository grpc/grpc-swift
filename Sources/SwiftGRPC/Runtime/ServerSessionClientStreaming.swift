/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

import Dispatch
import Foundation
import SwiftProtobuf

public protocol ServerSessionClientStreaming: ServerSession {}

open class ServerSessionClientStreamingBase<InputType: Message, OutputType: Message>: ServerSessionBase, ServerSessionClientStreaming, StreamReceiving {
  public typealias ReceivedType = InputType
  
  public typealias ProviderBlock = (ServerSessionClientStreamingBase) throws -> OutputType?
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }
  
  public func sendAndClose(response: OutputType, status: ServerStatus = .ok,
                           completion: (() -> Void)? = nil) throws {
    try handler.sendResponse(message: response.serializedData(), status: status, completion: completion)
  }

  public func sendErrorAndClose(status: ServerStatus, completion: (() -> Void)? = nil) throws {
    try handler.sendStatus(status, completion: completion)
  }
  
  public func run() throws -> ServerStatus? {
    try sendInitialMetadataAndWait()
    
    let responseMessage: OutputType
    do {
      guard let handlerResponse = try self.providerBlock(self) else {
        // This indicates that the provider blocks has taken responsibility for sending a response and status, so do
        // nothing.
        return nil
      }
      responseMessage = handlerResponse
    } catch {
      // Errors thrown by `providerBlock` should be logged in that method;
      // we return the error as a status code to avoid `ServiceServer` logging this as a "really unexpected" error.
      return (error as? ServerStatus) ?? .processingError
    }
    
    try self.sendAndClose(response: responseMessage)
    return nil  // The status will already be sent by `sendAndClose` above.
  }
}

/// Simple fake implementation of ServerSessionClientStreaming that returns a previously-defined result
/// and stores sent values for later verification.
open class ServerSessionClientStreamingTestStub<InputType: Message, OutputType: Message>: ServerSessionTestStub, ServerSessionClientStreaming {
  open var lock = Mutex()
  
  open var inputs: [InputType] = []
  open var output: OutputType?
  open var status: ServerStatus?

  open func _receive(timeout: DispatchTime) throws -> InputType? {
    return lock.synchronize {
      defer { if !inputs.isEmpty { inputs.removeFirst() } }
      return inputs.first
    }
  }
  
  open func receive(completion: @escaping (ResultOrRPCError<InputType?>) -> Void) throws {
    completion(.result(try self._receive(timeout: .distantFuture)))
  }

  open func sendAndClose(response: OutputType, status: ServerStatus, completion: (() -> Void)?) throws {
    lock.synchronize {
      self.output = response
      self.status = status
    }
    completion?()
  }

  open func sendErrorAndClose(status: ServerStatus, completion: (() -> Void)? = nil) throws {
    lock.synchronize {
      self.status = status
    }
    completion?()
  }
  
  open func close() throws {}
}
