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

open class ClientCallBidirectionalStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallBidirectionalStreaming, StreamReceiving, StreamSending {
  public typealias ReceivedType = OutputType
  public typealias SentType = InputType
  
  /// Call this to start a call. Nonblocking.
  public func start(metadata: Metadata, completion: ((CallResult) -> Void)?)
    throws -> Self {
    try call.start(.bidiStreaming, metadata: metadata, completion: completion)
    return self
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
}

/// Simple fake implementation of ClientCallBidirectionalStreamingBase that returns a previously-defined set of results
/// and stores sent values for later verification.
open class ClientCallBidirectionalStreamingTestStub<InputType: Message, OutputType: Message>: ClientCallBidirectionalStreaming {
  open class var method: String { fatalError("needs to be overridden") }

  open var inputs: [InputType] = []
  open var outputs: [OutputType] = []
  
  public init() {}

  open func _receive(timeout: DispatchTime) throws -> OutputType? {
    defer { if !outputs.isEmpty { outputs.removeFirst() } }
    return outputs.first
  }
  
  open func receive(completion: @escaping (ResultOrRPCError<OutputType?>) -> Void) throws {
    completion(.result(try self._receive(timeout: .distantFuture)))
  }

  open func send(_ message: InputType, completion _: @escaping (Error?) -> Void) throws {
    inputs.append(message)
  }
  
  open func _send(_ message: InputType, timeout: DispatchTime) throws {
    inputs.append(message)
  }

  open func closeSend(completion: (() -> Void)?) throws { completion?() }

  open func closeSend() throws {}

  open func waitForSendOperationsToFinish() {}

  open func cancel() {}
}
