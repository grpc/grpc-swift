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

public protocol ClientCallUnary: class {
  static var method: String { get }

  /// Cancel the call.
  func cancel()
}

open class ClientCallUnaryImpl<InputType: Message, OutputType: Message>: ClientCallUnary {
  open class var method: String { fatalError("needs to be overridden") }

  private var call: Call

  /// Create a call.
  public init(_ channel: Channel) {
    call = channel.makeCall(type(of: self).method)
  }

  /// Run the call. Blocks until the reply is received.
  /// - Throws: `BinaryEncodingError` if encoding fails. `CallError` if fails to call. `ClientError` if receives no response.
  public func run(request: InputType, metadata: Metadata) throws -> OutputType {
    let sem = DispatchSemaphore(value: 0)
    var returnCallResult: CallResult!
    var returnResponse: OutputType?
    _ = try start(request: request, metadata: metadata) { response, callResult in
      returnResponse = response
      returnCallResult = callResult
      sem.signal()
    }
    _ = sem.wait(timeout: DispatchTime.distantFuture)
    if let returnResponse = returnResponse {
      return returnResponse
    } else {
      throw ClientError.error(c: returnCallResult)
    }
  }

  /// Start the call. Nonblocking.
  /// - Throws: `BinaryEncodingError` if encoding fails. `CallError` if fails to call.
  public func start(request: InputType,
                    metadata: Metadata,
                    completion: @escaping ((OutputType?, CallResult) -> Void)) throws -> Self {
    let requestData = try request.serializedData()
    try call.start(.unary, metadata: metadata, message: requestData) { callResult in
      if let responseData = callResult.resultData,
        let response = try? OutputType(serializedData: responseData) {
        completion(response, callResult)
      } else {
        completion(nil, callResult)
      }
    }
    return self
  }

  public func cancel() {
    call.cancel()
  }
}
