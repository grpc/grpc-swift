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

/// Abstract base class exposing a method that exposes a promise for the RPC response.
///
/// - When `responsePromise` is fulfilled, the call is closed and the provided response transmitted with status `responseStatus` (`.ok` by default).
/// - If `statusPromise` is failed and the error is of type `GRPCStatusTransformable`,
///   the result of `error.asGRPCStatus()` will be returned to the client.
/// - If `error.asGRPCStatus()` is not available, `GRPCStatus.processingError` is returned to the client.
///
/// For unary calls, the response is not actually provided by fulfilling `responsePromise`, but instead by completing
/// the future returned by `UnaryCallHandler.EventObserver`.
open class UnaryResponseCallContext<ResponsePayload>: ServerCallContextBase, StatusOnlyCallContext {
  typealias WrappedResponse = GRPCServerResponsePart<ResponsePayload>

  public let responsePromise: EventLoopPromise<ResponsePayload>
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

  @available(*, deprecated, renamed: "init(eventLoop:headers:logger:userInfo:)")
  override public init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.responsePromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, request: request, logger: logger)
  }
}

/// Protocol variant of `UnaryResponseCallContext` that only exposes the `responseStatus` and `trailingMetadata`
/// fields, but not `responsePromise`.
///
/// Motivation: `UnaryCallHandler` already asks the call handler return an `EventLoopFuture<ResponsePayload>` which
/// is automatically cascaded into `UnaryResponseCallContext.responsePromise`, so that promise does not (and should not)
/// be fulfilled by the user.
///
/// We can use a protocol (instead of an abstract base class) here because removing the generic `responsePromise` field
/// lets us avoid associated-type requirements on the protocol.
public protocol StatusOnlyCallContext: ServerCallContext {
  var responseStatus: GRPCStatus { get set }
  var trailers: HPACKHeaders { get set }
}

extension StatusOnlyCallContext {
  @available(*, deprecated, renamed: "trailers")
  public var trailingMetadata: HTTPHeaders {
    get {
      return HTTPHeaders(self.trailers.map { ($0.name, $0.value) })
    }
    set {
      self.trailers = HPACKHeaders(httpHeaders: newValue)
    }
  }
}

/// Concrete implementation of `UnaryResponseCallContext` used by our generated code.
open class UnaryResponseCallContextImpl<ResponsePayload>: UnaryResponseCallContext<ResponsePayload> {
  public let channel: Channel

  /// - Parameters:
  ///   - channel: The NIO channel the call is handled on.
  ///   - headers: The headers provided with this call.
  ///   - errorDelegate: Provides a means for transforming response promise failures to `GRPCStatusTransformable` before
  ///     sending them to the client.
  ///   - logger: A logger.
  public init(
    channel: Channel,
    headers: HPACKHeaders,
    errorDelegate: ServerErrorDelegate?,
    logger: Logger
  ) {
    self.channel = channel
    super.init(
      eventLoop: channel.eventLoop,
      headers: headers,
      logger: logger,
      userInfoRef: .init(UserInfo())
    )

    self.responsePromise.futureResult.whenComplete { [self, weak errorDelegate] result in
      switch result {
      case let .success(message):
        self.handleResponse(message)

      case let .failure(error):
        self.handleError(error, delegate: errorDelegate)
      }
    }
  }

  /// Handle the response from the service provider.
  private func handleResponse(_ response: ResponsePayload) {
    self.channel.write(
      self.wrap(.message(response, .init(compress: self.compressionEnabled, flush: false))),
      promise: nil
    )

    self.channel.writeAndFlush(
      self.wrap(.end(self.responseStatus, self.trailers)),
      promise: nil
    )
  }

  /// Handle an error from the service provider.
  private func handleError(_ error: Error, delegate: ServerErrorDelegate?) {
    let (status, trailers) = self.processObserverError(error, delegate: delegate)
    self.channel.writeAndFlush(self.wrap(.end(status, trailers)), promise: nil)
  }

  /// Wrap the response part in a `NIOAny`. This is useful in order to avoid explicitly spelling
  /// out `NIOAny(WrappedResponse(...))`.
  private func wrap(_ response: WrappedResponse) -> NIOAny {
    return NIOAny(response)
  }

  @available(*, deprecated, renamed: "init(channel:headers:errorDelegate:logger:)")
  public convenience init(
    channel: Channel,
    request: HTTPRequestHead,
    errorDelegate: ServerErrorDelegate?,
    logger: Logger
  ) {
    self.init(
      channel: channel,
      headers: HPACKHeaders(httpHeaders: request.headers, normalizeHTTPHeaders: false),
      errorDelegate: errorDelegate,
      logger: logger
    )
  }
}

/// Concrete implementation of `UnaryResponseCallContext` used for testing.
///
/// Only provided to make it clear in tests that no "real" implementation is used.
open class UnaryResponseCallContextTestStub<ResponsePayload>: UnaryResponseCallContext<ResponsePayload> {}
