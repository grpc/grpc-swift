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
  func waitForSendOperationsToFinish()

  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallClientStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallClientStreaming, StreamSending {
  public typealias SentType = InputType
  
  /// Call this to start a call. Nonblocking.
  public func start(metadata: Metadata, completion: ((CallResult) -> Void)?) throws -> Self {
    try call.start(.clientStreaming, metadata: metadata, completion: completion)
    return self
  }

  public func closeAndReceive(completion: @escaping (ResultOrRPCError<OutputType>) -> Void) throws {
    try call.closeAndReceiveMessage { callResult in
      guard let responseData = callResult.resultData else {
        completion(.error(.callError(callResult))); return
      }
      if let response = try? OutputType(serializedData: responseData) {
        completion(.result(response))
      } else {
        completion(.error(.invalidMessageReceived))
      }
    }
  }

  public func closeAndReceive() throws -> OutputType {
    var result: ResultOrRPCError<OutputType>?
    let sem = DispatchSemaphore(value: 0)
    try closeAndReceive {
      result = $0
      sem.signal()
    }
    _ = sem.wait()
    switch result! {
    case .result(let response): return response
    case .error(let error): throw error
    }
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
  
  open func _send(_ message: InputType, timeout: DispatchTime) throws {
    inputs.append(message)
  }

  open func closeAndReceive(completion: @escaping (ResultOrRPCError<OutputType>) -> Void) throws {
    completion(.result(output!))
  }

  open func closeAndReceive() throws -> OutputType {
    return output!
  }

  open func waitForSendOperationsToFinish() {}
  
  open func cancel() {}
}
