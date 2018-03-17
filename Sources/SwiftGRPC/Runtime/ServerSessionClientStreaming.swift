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
  
  public typealias ProviderBlock = (ServerSessionClientStreamingBase) throws -> Void
  private var providerBlock: ProviderBlock

  public init(handler: Handler, providerBlock: @escaping ProviderBlock) {
    self.providerBlock = providerBlock
    super.init(handler: handler)
  }
  
  public func sendAndClose(response: OutputType, status: ServerStatus = .ok,
                           completion: ((CallResult) -> Void)? = nil) throws {
    try handler.sendResponse(message: response.serializedData(), status: status, completion: completion)
  }

  public func sendErrorAndClose(status: ServerStatus, completion: ((CallResult) -> Void)? = nil) throws {
    try handler.sendStatus(status, completion: completion)
  }
  
  public func run(queue: DispatchQueue) throws {
    try handler.sendMetadata(initialMetadata: initialMetadata) { success in
      queue.async {
        var responseStatus: ServerStatus?
        if success {
          do {
            try self.providerBlock(self)
          } catch {
            responseStatus = (error as? ServerStatus) ?? .processingError
          }
        } else {
          print("ServerSessionClientStreamingBase.run sending initial metadata failed")
          responseStatus = .sendingInitialMetadataFailed
        }
        
        if let responseStatus = responseStatus {
          // Error encountered, notify the client.
          do {
            try self.handler.sendStatus(responseStatus)
          } catch {
            print("ServerSessionClientStreamingBase.run error sending status: \(error)")
          }
        }
      }
    }
  }
}

/// Simple fake implementation of ServerSessionClientStreaming that returns a previously-defined result
/// and stores sent values for later verification.
open class ServerSessionClientStreamingTestStub<InputType: Message, OutputType: Message>: ServerSessionTestStub, ServerSessionClientStreaming {
  open var inputs: [InputType] = []
  open var output: OutputType?
  open var status: ServerStatus?

  open func receive() throws -> InputType? {
    defer { if !inputs.isEmpty { inputs.removeFirst() } }
    return inputs.first
  }
  
  open func receive(completion: @escaping (ResultOrRPCError<InputType?>) -> Void) throws {
    completion(.result(try self.receive()))
  }

  open func sendAndClose(response: OutputType, status: ServerStatus, completion: ((CallResult) -> Void)?) throws {
    self.output = response
    self.status = status
    completion?(.fakeOK)
  }

  open func sendErrorAndClose(status: ServerStatus, completion: ((CallResult) -> Void)? = nil) throws {
    self.status = status
    completion?(.fakeOK)
  }
  
  open func close() throws {}
}
