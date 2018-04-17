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
  // TODO: Move the other, message type-dependent, methods into this protocol. At the moment, this is not possible,
  // as the protocol would then have an associated type requirement (and become pretty much unusable in the process).
}

open class ClientCallServerStreamingBase<InputType: Message, OutputType: Message>: ClientCallBase, ClientCallServerStreaming, StreamReceiving {
  public typealias ReceivedType = OutputType
  
  /// Call this once with the message to send. Nonblocking.
  public func start(request: InputType, metadata: Metadata, completion: ((CallResult) -> Void)?) throws -> Self {
    let requestData = try request.serializedData()
    try call.start(.serverStreaming,
                   metadata: metadata,
                   message: requestData,
                   completion: completion)
    return self
  }
}

/// Simple fake implementation of ClientCallServerStreamingBase that returns a previously-defined set of results.
open class ClientCallServerStreamingTestStub<OutputType: Message>: ClientCallServerStreaming {
  open class var method: String { fatalError("needs to be overridden") }

  open var outputs: [OutputType] = []
  
  public init() {}
  
  open func _receive(timeout: DispatchTime) throws -> OutputType? {
    defer { if !outputs.isEmpty { outputs.removeFirst() } }
    return outputs.first
  }
  
  open func receive(completion: @escaping (ResultOrRPCError<OutputType?>) -> Void) throws {
    completion(.result(try self._receive(timeout: .distantFuture)))
  }

  open func cancel() {}
}
