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

import Foundation
import Dispatch
import SwiftProtobuf

public protocol ServerSessionUnary: ServerSession { }

open class ServerSessionUnaryImpl<InputType: Message, OutputType: Message>: ServerSessionImpl, ServerSessionUnary {
  public typealias ProviderBlock = (InputType, ServerSessionUnaryImpl) throws -> OutputType
  private var providerBlock: ProviderBlock
  
  public init(handler:Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler:handler)
  }
  
  public func run(queue:DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata:initialMetadata) {(requestData) in
      if let requestData = requestData {
        let requestMessage = try InputType(serializedData:requestData)
        let replyMessage = try self.providerBlock(requestMessage, self)
        try self.handler.sendResponse(message:replyMessage.serializedData(),
                                      statusCode:self.statusCode,
                                      statusMessage:self.statusMessage,
                                      trailingMetadata:self.trailingMetadata)
      }
    }
  }
}

/// Trivial fake implementation of ServerSessionUnary.
open class ServerSessionUnaryTestStub: ServerSessionTestStub, ServerSessionUnary { }
