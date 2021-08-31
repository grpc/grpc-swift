/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.5)

import Logging
import NIOConcurrencyHelpers
import NIOHPACK

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public final class GRPCAsyncServerCallContext {
  private let lock = Lock()

  /// Request headers for this request.
  public let headers: HPACKHeaders

  /// The logger used for this call.
  public let logger: Logger

  /// Whether compression should be enabled for responses, defaulting to `true`. Note that for
  /// this value to take effect compression must have been enabled on the server and a compression
  /// algorithm must have been negotiated with the client.
  public var compressionEnabled: Bool {
    get { self.lock.withLock {
      self._compressionEnabled
    } }
    set { self.lock.withLock {
      self._compressionEnabled = newValue
    } }
  }

  private var _compressionEnabled: Bool = true

  /// A `UserInfo` dictionary which is shared with the interceptor contexts for this RPC.
  ///
  /// - Important: While `UserInfo` has value-semantics, this property retrieves from, and sets a
  ///   reference wrapped `UserInfo`. The contexts passed to interceptors provide the same
  ///   reference. As such this may be used as a mechanism to pass information between interceptors
  ///   and service providers.
  public var userInfo: UserInfo {
    get { self.lock.withLock {
      self.userInfoRef.value
    } }
    set { self.lock.withLock {
      self.userInfoRef.value = newValue
    } }
  }

  /// A reference to an underlying `UserInfo`. We share this with the interceptors.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// Metadata to return at the end of the RPC. If this is required it should be updated before
  /// the `responsePromise` or `statusPromise` is fulfilled.
  public var trailers: HPACKHeaders {
    get { self.lock.withLock {
      return self._trailers
    } }
    set { self.lock.withLock {
      self._trailers = newValue
    } }
  }

  private var _trailers: HPACKHeaders = [:]

  public convenience init(
    headers: HPACKHeaders,
    logger: Logger,
    userInfo: UserInfo = UserInfo()
  ) {
    self.init(
      headers: headers,
      logger: logger,
      userInfoRef: .init(userInfo)
    )
  }

  @inlinable
  internal init(
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>
  ) {
    self.headers = headers
    self.userInfoRef = userInfoRef
    self.logger = logger
  }
}

#endif
