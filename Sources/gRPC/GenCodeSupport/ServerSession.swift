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

  var statusCode: StatusCode { get }
  var statusMessage: String { get }
  var initialMetadata: Metadata { get }
  var trailingMetadata: Metadata { get }
}

open class ServerSessionImpl: ServerSession {
  public var handler: Handler
  public var requestMetadata: Metadata { return handler.requestMetadata }

  public var statusCode: StatusCode = .ok
  public var statusMessage: String = "OK"
  public var initialMetadata: Metadata = Metadata()
  public var trailingMetadata: Metadata = Metadata()

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
}
