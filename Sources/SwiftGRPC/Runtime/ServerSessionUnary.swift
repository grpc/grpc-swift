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
  
  public func run() throws {
    try handler.receiveMessage(initialMetadata: initialMetadata) { requestData in
      let handlerThreadQueue = DispatchQueue(label: "SwiftGRPC.ServerSessionUnaryBase.run.handlerThread")
      handlerThreadQueue.async {
        let responseStatus: ServerStatus
        if let requestData = requestData {
          do {
            let requestMessage = try InputType(serializedData: requestData)
            let responseMessage = try self.providerBlock(requestMessage, self)
            try self.handler.call.sendMessage(data: responseMessage.serializedData()) {
              guard let error = $0
                else { return }
              print("ServerSessionUnaryBase.run error sending response: \(error)")
            }
            responseStatus = .ok
          } catch {
            responseStatus = (error as? ServerStatus) ?? .processingError
          }
        } else {
          print("ServerSessionUnaryBase.run empty request data")
          responseStatus = .noRequestData
        }
        
        do {
          try self.handler.sendStatus(responseStatus)
        } catch {
          print("ServerSessionUnaryBase.run error sending status: \(error)")
        }
      }
    }
  }
}

/// Trivial fake implementation of ServerSessionUnary.
open class ServerSessionUnaryTestStub: ServerSessionTestStub, ServerSessionUnary {}
