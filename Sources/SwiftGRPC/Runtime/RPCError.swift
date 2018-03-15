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

import Foundation

/// Type for errors thrown from generated client code.
public enum RPCError: Error {
  case invalidMessageReceived
  case callError(CallResult)
}

public extension RPCError {
  var callResult: CallResult? {
    switch self {
    case .invalidMessageReceived: return nil
    case .callError(let callResult): return callResult
    }
  }
}


public enum ResultOrRPCError<ResultType> {
  case result(ResultType)
  case error(RPCError)
}

public extension ResultOrRPCError {
  var result: ResultType? {
    switch self {
    case .result(let result): return result
    case .error: return nil
    }
  }
  
  var error: RPCError? {
    switch self {
    case .result: return nil
    case .error(let error): return error
    }
  }
}

