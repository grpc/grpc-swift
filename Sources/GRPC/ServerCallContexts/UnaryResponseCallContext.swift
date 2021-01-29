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

/// A context provided to handlers for RPCs which return a single response, i.e. unary and client
/// streaming RPCs.
///
/// For client streaming RPCs the handler must complete the `responsePromise` to return the response
/// to the client. Unary RPCs do complete the promise directly: they are provided an
/// `StatusOnlyCallContext` view of this context where the `responsePromise` is not exposed. Instead
/// they must return an `EventLoopFuture<Response>` from the method they are implementing.
open class UnaryResponseCallContext<Response>: ServerCallContextBase, StatusOnlyCallContext {
  /// A promise for a single response message. This must be completed to send a response back to the
  /// client. If the promise is failed, the failure value will be converted to `GRPCStatus` and
  /// used as the final status for the RPC.
  public let responsePromise: EventLoopPromise<Response>

  /// The status sent back to the client at the end of the RPC, providing the `responsePromise` was
  /// completed successfully.
  public var responseStatus: GRPCStatus = .ok

  public convenience init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfo: UserInfo = UserInfo()
  ) {
    self.init(eventLoop: eventLoop, headers: headers, logger: logger, userInfoRef: .init(userInfo))
  }

  @inlinable
  override internal init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>
  ) {
    self.responsePromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, headers: headers, logger: logger, userInfoRef: userInfoRef)
  }
}

/// Protocol variant of `UnaryResponseCallContext` that only exposes the `responseStatus` and `trailingMetadata`
/// fields, but not `responsePromise`.
///
/// We can use a protocol (instead of an abstract base class) here because removing the generic
/// `responsePromise` field lets us avoid associated-type requirements on the protocol.
public protocol StatusOnlyCallContext: ServerCallContext {
  /// The status sent back to the client at the end of the RPC, providing the `responsePromise` was
  /// completed successfully.
  var responseStatus: GRPCStatus { get set }

  /// Metadata to return at the end of the RPC.
  var trailers: HPACKHeaders { get set }
}

/// Concrete implementation of `UnaryResponseCallContext` used for testing.
///
/// Only provided to make it clear in tests that no "real" implementation is used.
open class UnaryResponseCallContextTestStub<Response>: UnaryResponseCallContext<Response> {}
