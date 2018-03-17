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

public protocol StreamSending {
  associatedtype SentType: Message
  
  var call: Call { get }
}

extension StreamSending {
  public func send(_ message: SentType, completion: @escaping (Error?) -> Void) throws {
    try call.sendMessage(data: message.serializedData(), completion: completion)
  }
  
  public func send(_ message: SentType) throws {
    var resultError: Error?
    let sem = DispatchSemaphore(value: 0)
    try send(message) {
      resultError = $0
      sem.signal()
    }
    _ = sem.wait()
    if let resultError = resultError {
      throw resultError
    }
  }
  
  public func waitForSendOperationsToFinish() {
    call.messageQueueEmpty.wait()
  }
}

extension StreamSending where Self: ServerSessionBase {
  public func close(withStatus status: ServerStatus = .ok, completion: (() -> Void)? = nil) throws {
    try handler.sendStatus(status, completion: completion)
  }
}
