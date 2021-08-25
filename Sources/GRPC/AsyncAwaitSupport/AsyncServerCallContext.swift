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
import Logging
import NIOHPACK

#if compiler(>=5.5)

/// A context provided to RPC handlers.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol AsyncServerCallContext /* Do we want this to be an actor? */ {
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

  /// Metadata to return at the end of the RPC. If this is required it should be updated before
  /// returning from the handler.
  var trailers: HPACKHeaders { get set }
}

/// The intention is that we will provide a new concrete implementation of `AsyncServerCallContext`
/// that is independent of the existing `ServerCallContext` family of classes. But for now we just
/// provide a view over the existing ones to get us going.
extension ServerCallContextBase: AsyncServerCallContext {}

#endif
