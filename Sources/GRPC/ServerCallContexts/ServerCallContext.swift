/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Logging
import NIO
import NIOHTTP1
import SwiftProtobuf

/// Protocol declaring a minimum set of properties exposed by *all* types of call contexts.
public protocol ServerCallContext: AnyObject {
  /// The event loop this call is served on.
  var eventLoop: EventLoop { get }

  /// Generic metadata provided with this request.
  var request: HTTPRequestHead { get }

  /// The logger used for this call.
  var logger: Logger { get }

  /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
  /// this value to take effect compression must have been enabled on the server and a compression
  /// algorithm must have been negotiated with the client.
  var compressionEnabled: Bool { get set }
}

/// Base class providing data provided to the framework user for all server calls.
open class ServerCallContextBase: ServerCallContext {
  public let eventLoop: EventLoop
  public let request: HTTPRequestHead
  public let logger: Logger
  public var compressionEnabled: Bool = true

  /// Metadata to return at the end of the RPC. If this is required it should be updated before
  /// the `responsePromise` or `statusPromise` is fulfilled.
  public var trailingMetadata = HTTPHeaders()

  public init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.eventLoop = eventLoop
    self.request = request
    self.logger = logger
  }
}
