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

public protocol ServerSessionBidirectionalStreaming: ServerSession {
  func waitForSendOperationsToFinish()
}

open class ServerSessionBidirectionalStreamingBase<InputType: Message, OutputType: Message>: ServerSessionBase, ServerSessionBidirectionalStreaming {
  public typealias ProviderBlock = (ServerSessionBidirectionalStreamingBase) throws -> Void
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }

  public func receive() throws -> InputType {
    let sem = DispatchSemaphore(value: 0)
    var requestMessage: InputType?
    try handler.receiveMessage { requestData in
      if let requestData = requestData {
        do {
          requestMessage = try InputType(serializedData: requestData)
        } catch (let error) {
          print("error \(error)")
        }
      }
      sem.signal()
    }
    _ = sem.wait()
    if let requestMessage = requestMessage {
      return requestMessage
    } else {
      throw ServerError.endOfStream
    }
  }

  public func send(_ response: OutputType, completion: ((Error?) -> Void)?) throws {
    try handler.sendResponse(message: response.serializedData(), completion: completion)
  }

  public func close() throws {
    let sem = DispatchSemaphore(value: 0)
    try handler.sendStatus(statusCode: statusCode,
                           statusMessage: statusMessage,
                           trailingMetadata: trailingMetadata) { _ in sem.signal() }
    _ = sem.wait()
  }

  public func run(queue: DispatchQueue) throws {
    try handler.sendMetadata(initialMetadata: initialMetadata) { _ in
      queue.async {
        do {
          try self.providerBlock(self)
        } catch (let error) {
          print("error \(error)")
        }
      }
    }
  }

  public func waitForSendOperationsToFinish() {
    handler.call.messageQueueEmpty.wait()
  }
}

/// Simple fake implementation of ServerSessionBidirectionalStreaming that returns a previously-defined set of results
/// and stores sent values for later verification.
open class ServerSessionBidirectionalStreamingTestStub<InputType: Message, OutputType: Message>: ServerSessionTestStub, ServerSessionBidirectionalStreaming {
  open var inputs: [InputType] = []
  open var outputs: [OutputType] = []

  open func receive() throws -> InputType {
    if let input = inputs.first {
      inputs.removeFirst()
      return input
    } else {
      throw ServerError.endOfStream
    }
  }

  open func send(_ response: OutputType, completion _: ((Error?) -> Void)?) throws {
    outputs.append(response)
  }

  open func close() throws {}

  open func waitForSendOperationsToFinish() {}
}
