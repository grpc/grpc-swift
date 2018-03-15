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
  public typealias ProviderBlock = (InputType, ServerSessionUnaryBase) throws -> OutputType
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }
  
  public func run(queue _: DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata: initialMetadata) { requestData in
      guard let requestData = requestData else {
        print("ServerSessionUnaryBase.run empty request data")
        do {
          try self.handler.sendStatus(statusCode: .invalidArgument,
                                      statusMessage: "no request data received")
        } catch {
          print("ServerSessionUnaryBase.run error sending status: \(error)")
        }
        return
      }
      do {
        let requestMessage = try InputType(serializedData: requestData)
        let replyMessage = try self.providerBlock(requestMessage, self)
        try self.handler.sendResponse(message: replyMessage.serializedData(),
                                      statusCode: self.statusCode,
                                      statusMessage: self.statusMessage,
                                      trailingMetadata: self.trailingMetadata)
      } catch {
        print("ServerSessionUnaryBase.run error processing request: \(error)")
        
        do {
          try self.handler.sendError((error as? ServerErrorStatus)
            ?? ServerErrorStatus(statusCode: .unknown, statusMessage: "unknown error processing request"))
        } catch {
          print("ServerSessionUnaryBase.run error sending status: \(error)")
        }
      }
    }
  }
}

/// Trivial fake implementation of ServerSessionUnary.
open class ServerSessionUnaryTestStub: ServerSessionTestStub, ServerSessionUnary {}
