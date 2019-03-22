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

public protocol StreamReceiving {
  associatedtype ReceivedType: Message
  
  var call: Call { get }
}

extension StreamReceiving {
  public func receive(completion: @escaping (ResultOrRPCError<ReceivedType?>) -> Void) throws {
    try call.receiveMessage { callResult in
      guard let responseData = callResult.resultData else {
        if callResult.success {
          completion(.result(nil))
        } else {
          completion(.error(.callError(callResult)))
        }
        return
      }
      if let response = try? ReceivedType(serializedData: responseData) {
        completion(.result(response))
      } else {
        completion(.error(.invalidMessageReceived))
      }
    }
  }
  
  public func _receive(timeout: DispatchTime) throws -> ReceivedType? {
    var result: ResultOrRPCError<ReceivedType?>?
    let sem = DispatchSemaphore(value: 0)
    try receive {
      result = $0
      sem.signal()
    }
    if sem.wait(timeout: timeout) == .timedOut {
      throw RPCError.timedOut
    }
    switch result! {
    case .result(let response): return response
    case .error(let error): throw error
    }
  }
}
