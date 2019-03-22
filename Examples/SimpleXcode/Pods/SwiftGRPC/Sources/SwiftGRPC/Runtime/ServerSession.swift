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

public protocol ServerSession: class {
  var requestMetadata: Metadata { get }

  var initialMetadata: Metadata { get set }
  
  func cancel()
}

open class ServerSessionBase: ServerSession {
  public var handler: Handler
  public var requestMetadata: Metadata { return handler.requestMetadata }

  public var initialMetadata: Metadata = Metadata()
  
  public var call: Call { return handler.call }

  public init(handler: Handler) {
    self.handler = handler
  }
  
  public func cancel() {
    call.cancel()
    handler.shutdown()
  }
  
  func sendInitialMetadataAndWait() throws {
    let sendMetadataSignal = DispatchSemaphore(value: 0)
    var success = false
    try handler.sendMetadata(initialMetadata: initialMetadata) {
      success = $0
      sendMetadataSignal.signal()
    }
    sendMetadataSignal.wait()
    
    if !success {
      throw ServerStatus.sendingInitialMetadataFailed
    }
  }
  
  func receiveRequestAndWait() throws -> Data {
    let sendMetadataSignal = DispatchSemaphore(value: 0)
    var requestData: Data?
    try handler.receiveMessage(initialMetadata: initialMetadata) {
      requestData = $0
      sendMetadataSignal.signal()
    }
    sendMetadataSignal.wait()
    
    if let requestData = requestData {
      return requestData
    } else {
      throw ServerStatus.noRequestData
    }
  }
}

open class ServerSessionTestStub: ServerSession {
  open var requestMetadata = Metadata()

  open var initialMetadata = Metadata()

  public init() {}
  
  open func cancel() {}
}
