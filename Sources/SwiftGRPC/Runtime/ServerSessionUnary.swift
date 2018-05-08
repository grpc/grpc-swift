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

public protocol ServerSessionUnary: ServerSession {}

open class ServerSessionUnaryBase<InputType: Message, OutputType: Message>: ServerSessionBase, ServerSessionUnary {
  public typealias SentType = OutputType
  
  public typealias ProviderBlock = (InputType, ServerSessionUnaryBase) throws -> OutputType
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }
  
  public func run() throws -> ServerStatus? {
    let requestData = try receiveRequestAndWait()
    let requestMessage = try InputType(serializedData: requestData)
    
    let responseMessage: OutputType
    do {
      responseMessage = try self.providerBlock(requestMessage, self)
    } catch {
      // Errors thrown by `providerBlock` should be logged in that method;
      // we return the error as a status code to avoid `ServiceServer` logging this as a "really unexpected" error.
      return (error as? ServerStatus) ?? .processingError
    }
    
    let sendResponseSignal = DispatchSemaphore(value: 0)
    var sendResponseError: Error?
    try self.handler.call.sendMessage(data: responseMessage.serializedData()) {
      sendResponseError = $0
      sendResponseSignal.signal()
    }
    sendResponseSignal.wait()
    if let sendResponseError = sendResponseError {
      throw sendResponseError
    }
    
    return .ok
  }
}

/// Trivial fake implementation of ServerSessionUnary.
open class ServerSessionUnaryTestStub: ServerSessionTestStub, ServerSessionUnary {}
