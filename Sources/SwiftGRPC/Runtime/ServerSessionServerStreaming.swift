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

public protocol ServerSessionServerStreaming: ServerSession {
  func waitForSendOperationsToFinish()
}

open class ServerSessionServerStreamingBase<InputType: Message, OutputType: Message>: ServerSessionBase, ServerSessionServerStreaming, StreamSending {
  public typealias SentType = OutputType
  
  public typealias ProviderBlock = (InputType, ServerSessionServerStreamingBase) throws -> Void
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }
  
  public func run(queue: DispatchQueue) throws {
    try handler.receiveMessage(initialMetadata: initialMetadata) { requestData in
      let handlerThreadQueue = DispatchQueue(label: "SwiftGRPC.ServerSessionServerStreamingBase.run.handlerThread")
      handlerThreadQueue.async {
        var responseStatus: ServerStatus?
        if let requestData = requestData {
          do {
            let requestMessage = try InputType(serializedData: requestData)
            try self.providerBlock(requestMessage, self)
          } catch {
            responseStatus = (error as? ServerStatus) ?? .processingError
          }
        } else {
          print("ServerSessionServerStreamingBase.run empty request data")
          responseStatus = .noRequestData
        }
        
        if let responseStatus = responseStatus {
          // Error encountered, notify the client.
          do {
            try self.handler.sendStatus(responseStatus)
          } catch {
            print("ServerSessionServerStreamingBase.run error sending status: \(error)")
          }
        }
      }
    }
  }
}

/// Simple fake implementation of ServerSessionServerStreaming that returns a previously-defined set of results
/// and stores sent values for later verification.
open class ServerSessionServerStreamingTestStub<OutputType: Message>: ServerSessionTestStub, ServerSessionServerStreaming {
  open var lock = Mutex()
  
  open var outputs: [OutputType] = []
  open var status: ServerStatus?

  open func send(_ message: OutputType, completion _: @escaping (Error?) -> Void) throws {
    lock.synchronize { outputs.append(message) }
  }

  open func _send(_ message: OutputType, timeout: DispatchTime) throws {
    lock.synchronize { outputs.append(message) }
  }

  open func close(withStatus status: ServerStatus, completion: (() -> Void)?) throws {
    lock.synchronize { self.status = status }
    completion?()
  }

  open func waitForSendOperationsToFinish() {}
}
