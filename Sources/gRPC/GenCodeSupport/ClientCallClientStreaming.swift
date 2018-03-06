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

public protocol ClientCallClientStreaming: ClientCall {
  /// Cancel the call.
  func cancel()

  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallClientStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallClientStreaming {
  /// Call this to start a call. Nonblocking.
  public func start(metadata: Metadata, completion: ((CallResult) -> Void)?) throws -> Self {
    try call.start(.clientStreaming, metadata: metadata, completion: completion)
    return self
  }

  public func send(_ message: InputType, completion: @escaping (Error?) -> Void) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data: messageData, completion: completion)
  }

  public func closeAndReceive(completion: @escaping (OutputType?, ClientError?) -> Void) throws {
    do {
      try call.closeAndReceiveMessage { responseData in
        if let responseData = responseData,
          let response = try? OutputType(serializedData: responseData) {
          completion(response, nil)
        } else {
          completion(nil, .invalidMessageReceived)
        }
      }
    } catch (let error) {
      throw error
    }
  }

  public func closeAndReceive() throws -> OutputType {
    var returnError: ClientError?
    var returnResponse: OutputType!
    let sem = DispatchSemaphore(value: 0)
    do {
      try closeAndReceive { response, error in
        returnResponse = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait()
    } catch (let error) {
      throw error
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnResponse
  }

  public func cancel() {
    call.cancel()
  }
}

/// Simple fake implementation of ClientCallClientStreamingBase that
/// stores sent values for later verification and finally returns a previously-defined result.
open class ClientCallClientStreamingTestStub<InputType: Message, OutputType: Message>: ClientCallClientStreaming {
  open class var method: String { fatalError("needs to be overridden") }

  open var inputs: [InputType] = []
  open var output: OutputType?
  
  public init() {}

  open func send(_ message: InputType, completion _: @escaping (Error?) -> Void) throws {
    inputs.append(message)
  }

  open func closeAndReceive(completion: @escaping (OutputType?, ClientError?) -> Void) throws {
    completion(output!, nil)
  }

  open func closeAndReceive() throws -> OutputType {
    return output!
  }

  open func cancel() {}
}
