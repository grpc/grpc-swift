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

public protocol ServerSessionServerStreaming: ServerSession {}

open class ServerSessionServerStreamingBase<InputType: Message, OutputType: Message>: ServerSessionBase, ServerSessionServerStreaming {
  public typealias ProviderBlock = (InputType, ServerSessionServerStreamingBase) throws -> Void
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }

  public func send(_ response: OutputType, completion: ((Bool) -> Void)?) throws {
    try handler.sendResponse(message: response.serializedData(), completion: completion)
  }

  public func run(queue: DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata: initialMetadata) { requestData in
      if let requestData = requestData {
        do {
          let requestMessage = try InputType(serializedData: requestData)
          // to keep providers from blocking the server thread,
          // we dispatch them to another queue.
          queue.async {
            do {
              try self.providerBlock(requestMessage, self)
              try self.handler.sendStatus(statusCode: self.statusCode,
                                          statusMessage: self.statusMessage,
                                          trailingMetadata: self.trailingMetadata,
                                          completion: nil)
            } catch (let error) {
              print("error: \(error)")
            }
          }
        } catch (let error) {
          print("error: \(error)")
        }
      }
    }
  }
}

/// Simple fake implementation of ServerSessionServerStreaming that returns a previously-defined set of results
/// and stores sent values for later verification.
open class ServerSessionServerStreamingTestStub<OutputType: Message>: ServerSessionTestStub, ServerSessionServerStreaming {
  open var outputs: [OutputType] = []

  open func send(_ response: OutputType, completion _: ((Bool) -> Void)?) throws {
    outputs.append(response)
  }

  open func close() throws {}
}
