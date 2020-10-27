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

/// Abstract base class exposing a method to send multiple messages over the wire and a promise for the final RPC status.
///
/// - When `statusPromise` is fulfilled, the call is closed and the provided status transmitted.
/// - If `statusPromise` is failed and the error is of type `GRPCStatusTransformable`,
///   the result of `error.asGRPCStatus()` will be returned to the client.
/// - If `error.asGRPCStatus()` is not available, `GRPCStatus.processingError` is returned to the client.
open class StreamingResponseCallContext<ResponsePayload>: ServerCallContextBase {
  typealias WrappedResponse = _GRPCServerResponsePart<ResponsePayload>

  public let statusPromise: EventLoopPromise<GRPCStatus>

  override public init(eventLoop: EventLoop, headers: HPACKHeaders, logger: Logger) {
    self.statusPromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, headers: headers, logger: logger)
  }

  @available(*, deprecated, renamed: "init(eventLoop:path:headers:logger:)")
  override public init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.statusPromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, request: request, logger: logger)
  }

  /// Send a response to the client.
  ///
  /// - Parameter message: The message to send to the client.
  /// - Parameter compression: Whether compression should be used for this response. If compression
  ///   is enabled in the call context, the value passed here takes precedence. Defaults to deferring
  ///   to the value set on the call context.
  open func sendResponse(_ message: ResponsePayload,
                         compression: Compression = .deferToCallDefault) -> EventLoopFuture<Void> {
    fatalError("needs to be overridden")
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used by our generated code.
open class StreamingResponseCallContextImpl<ResponsePayload>: StreamingResponseCallContext<ResponsePayload> {
  public let channel: Channel

  /// - Parameters:
  ///   - channel: The NIO channel the call is handled on.
  ///   - headers: The headers provided with this call.
  ///   - errorDelegate: Provides a means for transforming status promise failures to `GRPCStatusTransformable` before
  ///     sending them to the client.
  ///   - logger: A logger.
  ///
  ///     Note: `errorDelegate` is not called for status promise that are `succeeded` with a non-OK status.
  public init(
    channel: Channel,
    headers: HPACKHeaders,
    errorDelegate: ServerErrorDelegate?,
    logger: Logger
  ) {
    self.channel = channel
    super.init(eventLoop: channel.eventLoop, headers: headers, logger: logger)

    self.statusPromise.futureResult.whenComplete { result in
      switch result {
      case let .success(status):
        self.channel.writeAndFlush(
          self.wrap(.statusAndTrailers(status, self.trailers)),
          promise: nil
        )

      case let .failure(error):
        let (status, trailers) = self.processError(error, delegate: errorDelegate)
        self.channel.writeAndFlush(self.wrap(.statusAndTrailers(status, trailers)), promise: nil)
      }
    }
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

  override open func sendResponse(
    _ message: ResponsePayload,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> {
    let messageContext = _MessageContext(
      message,
      compressed: compression.isEnabled(callDefault: self.compressionEnabled)
    )
    return self.channel.writeAndFlush(NIOAny(WrappedResponse.message(messageContext)))
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used for testing.
///
/// Simply records all sent messages.
open class StreamingResponseCallContextTestStub<ResponsePayload>: StreamingResponseCallContext<ResponsePayload> {
  open var recordedResponses: [ResponsePayload] = []

  override open func sendResponse(
    _ message: ResponsePayload,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> {
    self.recordedResponses.append(message)
    return eventLoop.makeSucceededFuture(())
  }
}
