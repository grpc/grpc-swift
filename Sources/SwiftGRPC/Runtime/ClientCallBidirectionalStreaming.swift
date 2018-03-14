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

public protocol ClientCallBidirectionalStreaming: ClientCall {
  func waitForSendOperationsToFinish()
  
  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallBidirectionalStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallBidirectionalStreaming {
  /// Call this to start a call. Nonblocking.
  public func start(metadata: Metadata, completion: ((CallResult) -> Void)?)
    throws -> Self {
    try call.start(.bidiStreaming, metadata: metadata, completion: completion)
    return self
  }

  public func receive(completion: @escaping (OutputType?, ClientError?) -> Void) throws {
    do {
      try call.receiveMessage { data in
        if let data = data {
          if let returnMessage = try? OutputType(serializedData: data) {
            completion(returnMessage, nil)
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
    var returnMessage: OutputType!
    let sem = DispatchSemaphore(value: 0)
    do {
      try receive { response, error in
        returnMessage = response
        returnError = error
        sem.signal()
      }
      _ = sem.wait()
    }
    if let returnError = returnError {
      throw returnError
    }
    return returnMessage
  }

  public func send(_ message: InputType, completion: @escaping (Error?) -> Void) throws {
    let messageData = try message.serializedData()
    try call.sendMessage(data: messageData, completion: completion)
  }

  public func closeSend(completion: (() -> Void)?) throws {
    try call.close(completion: completion)
  }

  public func closeSend() throws {
    let sem = DispatchSemaphore(value: 0)
    try closeSend {
      sem.signal()
    }
    _ = sem.wait()
  }
  
  public func waitForSendOperationsToFinish() {
    call.messageQueueEmpty.wait()
  }
}

/// Simple fake implementation of ClientCallBidirectionalStreamingBase that returns a previously-defined set of results
/// and stores sent values for later verification.
open class ClientCallBidirectionalStreamingTestStub<InputType: Message, OutputType: Message>: ClientCallBidirectionalStreaming {
  open class var method: String { fatalError("needs to be overridden") }

  open var inputs: [InputType] = []
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

  open func send(_ message: InputType, completion _: @escaping (Error?) -> Void) throws {
    inputs.append(message)
  }

  open func closeSend(completion: (() -> Void)?) throws { completion?() }

  open func closeSend() throws {}

  open func waitForSendOperationsToFinish() {}

  open func cancel() {}
}
