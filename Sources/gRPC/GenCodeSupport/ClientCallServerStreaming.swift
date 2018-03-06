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

public protocol ClientCallServerStreaming: ClientCall {
  /// Cancel the call.
  func cancel()

  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallServerStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallServerStreaming {
  /// Call this once with the message to send. Nonblocking.
  public func start(request: InputType, metadata: Metadata, completion: ((CallResult) -> Void)?) throws -> Self {
    let requestData = try request.serializedData()
    try call.start(.serverStreaming,
                   metadata: metadata,
                   message: requestData,
                   completion: completion)
    return self
  }

  public func receive(completion: @escaping (OutputType?, ClientError?) -> Void) throws {
    do {
      try call.receiveMessage { responseData in
        if let responseData = responseData {
          if let response = try? OutputType(serializedData: responseData) {
            completion(response, nil)
          } else {
            completion(nil, .invalidMessageReceived)
          }
        } else {
          completion(nil, .endOfStream)
        }
      }
    }
  }

  public func receive() throws -> OutputType {
    var returnError: ClientError?
    var returnResponse: OutputType!
    let sem = DispatchSemaphore(value: 0)
    do {
      try receive { response, error in
        returnResponse = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait()
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

/// Simple fake implementation of ClientCallServerStreamingBase that returns a previously-defined set of results.
open class ClientCallServerStreamingTestStub<OutputType: Message>: ClientCallServerStreaming {
  open class var method: String { fatalError("needs to be overridden") }

  open var outputs: [OutputType] = []
  
  public init() {}

  open func receive(completion: @escaping (OutputType?, ClientError?) -> Void) throws {
    if let output = outputs.first {
      outputs.removeFirst()
      completion(output, nil)
    } else {
      completion(nil, .endOfStream)
    }
  }

  open func receive() throws -> OutputType {
    if let output = outputs.first {
      outputs.removeFirst()
      return output
    } else {
      throw ClientError.endOfStream
    }
  }

  open func cancel() {}
}
