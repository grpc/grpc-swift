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
#if compiler(>=5.6)

import Logging
import NIOConcurrencyHelpers
import NIOHPACK

// We use a `class` here because we do not want copy-on-write semantics. The instance that the async
// handler holds must not diverge from the instance the implementor of the RPC holds. They hold these
// instances on different threads (EventLoop vs Task).
//
// We considered wrapping this in a `struct` and pass it `inout` to the RPC. This would communicate
// explicitly that it stores mutable state. However, without copy-on-write semantics, this could
// make for a surprising API.
//
// We also considered an `actor` but that felt clunky at the point of use since adopters would need
// to `await` the retrieval of a logger or the updating of the trailers and each would require a
// promise to glue the NIO and async-await paradigms in the handler.
//
// Note: this is `@unchecked Sendable`; all mutable state is protected by a lock.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class GRPCAsyncServerCallContext: @unchecked Sendable {
  private let lock = Lock()

  /// Metadata for this request.
  public let requestMetadata: HPACKHeaders

  /// The logger used for this call.
  public var logger: Logger {
    get { self.lock.withLock {
      self._logger
    } }
    set { self.lock.withLock {
      self._logger = newValue
    } }
  }

  @usableFromInline
  internal var _logger: Logger

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

  /// Metadata to return at the start of the RPC.
  ///
  /// - Important: If this is required it should be updated _before_ the first response is sent via
  /// the response stream writer. Any updates made after the first response will be ignored.
  public var initialResponseMetadata: HPACKHeaders {
    get { self.lock.withLock {
      return self._initialResponseMetadata
    } }
    set { self.lock.withLock {
      self._initialResponseMetadata = newValue
    } }
  }

  private var _initialResponseMetadata: HPACKHeaders = [:]

  /// Metadata to return at the end of the RPC.
  ///
  /// If this is required it should be updated before returning from the handler.
  public var trailingResponseMetadata: HPACKHeaders {
    get { self.lock.withLock {
      return self._trailingResponseMetadata
    } }
    set { self.lock.withLock {
      self._trailingResponseMetadata = newValue
    } }
  }

  private var _trailingResponseMetadata: HPACKHeaders = [:]

  @inlinable
  internal init(
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>
  ) {
    self.requestMetadata = headers
    self.userInfoRef = userInfoRef
    self._logger = logger
  }
}

#endif
