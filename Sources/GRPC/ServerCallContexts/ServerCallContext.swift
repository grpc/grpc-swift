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
import NIOHPACK
import NIOHTTP1
import SwiftProtobuf

/// Protocol declaring a minimum set of properties exposed by *all* types of call contexts.
public protocol ServerCallContext: AnyObject {
  /// The event loop this call is served on.
  var eventLoop: EventLoop { get }

  /// Request headers for this request.
  var headers: HPACKHeaders { get }

  /// A 'UserInfo' dictionary which is shared with the interceptor contexts for this RPC.
  var userInfo: UserInfo { get set }

  /// The logger used for this call.
  var logger: Logger { get }

  /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
  /// this value to take effect compression must have been enabled on the server and a compression
  /// algorithm must have been negotiated with the client.
  var compressionEnabled: Bool { get set }
}

/// Base class providing data provided to the framework user for all server calls.
open class ServerCallContextBase: ServerCallContext {
  /// The event loop this call is served on.
  public let eventLoop: EventLoop

  /// Request headers for this request.
  public let headers: HPACKHeaders

  /// The logger used for this call.
  public let logger: Logger

  /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
  /// this value to take effect compression must have been enabled on the server and a compression
  /// algorithm must have been negotiated with the client.
  public var compressionEnabled: Bool = true

  /// - Important: While `UserInfo` has value-semantics, this property retrieves from, and sets a
  ///   reference wrapped `UserInfo`. The contexts passed to interceptors provide the same
  ///   reference. As such this may be used as a mechanism to pass information between interceptors
  ///   and service providers.
  public var userInfo: UserInfo {
    get {
      return self.userInfoRef.value
    }
    set {
      self.userInfoRef.value = newValue
    }
  }

  /// A reference to an underlying `UserInfo`. We share this with the interceptors.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// Metadata to return at the end of the RPC. If this is required it should be updated before
  /// the `responsePromise` or `statusPromise` is fulfilled.
  public var trailers = HPACKHeaders()

  public convenience init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfo: UserInfo = UserInfo()
  ) {
    self.init(eventLoop: eventLoop, headers: headers, logger: logger, userInfoRef: .init(userInfo))
  }

  @inlinable
  internal init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>
  ) {
    self.eventLoop = eventLoop
    self.headers = headers
    self.userInfoRef = userInfoRef
    self.logger = logger
  }
}
