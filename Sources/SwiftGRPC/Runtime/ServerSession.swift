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

public struct ServerErrorStatus: Error {
  public let statusCode: StatusCode
  public let statusMessage: String
  public let trailingMetadata: Metadata
  
  public init(statusCode: StatusCode, statusMessage: String, trailingMetadata: Metadata = Metadata()) {
    self.statusCode = statusCode
    self.statusMessage = statusMessage
    self.trailingMetadata = trailingMetadata
  }
}

public protocol ServerSession: class {
  var requestMetadata: Metadata { get }

  var statusCode: StatusCode { get set }
  var statusMessage: String { get set }
  var initialMetadata: Metadata { get set }
  var trailingMetadata: Metadata { get set }
}

open class ServerSessionBase: ServerSession {
  public var handler: Handler
  public var requestMetadata: Metadata { return handler.requestMetadata }

  public var statusCode: StatusCode = .ok
  public var statusMessage: String = "OK"
  public var initialMetadata: Metadata = Metadata()
  public var trailingMetadata: Metadata = Metadata()
  
  public var call: Call { return handler.call }

  public init(handler: Handler) {
    self.handler = handler
  }
}

open class ServerSessionTestStub: ServerSession {
  open var requestMetadata = Metadata()

  open var statusCode = StatusCode.ok
  open var statusMessage = "OK"
  open var initialMetadata = Metadata()
  open var trailingMetadata = Metadata()

  public init() {}
}
