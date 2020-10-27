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
  /// - Parameters:
  ///   - message: The message to send to the client.
  ///   - compression: Whether compression should be used for this response. If compression
  ///     is enabled in the call context, the value passed here takes precedence. Defaults to
  ///     deferring to the value set on the call context.
  ///   - promise: A promise to complete once the message has been sent.
  open func sendResponse(
    _ message: ResponsePayload,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    fatalError("needs to be overridden")
  }

  /// Send a response to the client.
  ///
  /// - Parameters:
  ///   - message: The message to send to the client.
  ///   - compression: Whether compression should be used for this response. If compression
  ///     is enabled in the call context, the value passed here takes precedence. Defaults to
  ///     deferring to the value set on the call context.
  open func sendResponse(
    _ message: ResponsePayload,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.sendResponse(message, compression: compression, promise: promise)
    return promise.futureResult
  }

  /// Sends a sequence of responses to the client.
  /// - Parameters:
  ///   - messages: The messages to send to the client.
  ///   - compression: Whether compression should be used for this response. If compression
  ///     is enabled in the call context, the value passed here takes precedence. Defaults to
  ///     deferring to the value set on the call context.
  ///   - promise: A promise to complete once the messages have been sent.
  open func sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where Messages.Element == ResponsePayload {
    fatalError("needs to be overridden")
  }

  /// Sends a sequence of responses to the client.
  /// - Parameters:
  ///   - messages: The messages to send to the client.
  ///   - compression: Whether compression should be used for this response. If compression
  ///     is enabled in the call context, the value passed here takes precedence. Defaults to
  ///     deferring to the value set on the call context.
  open func sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression = .deferToCallDefault
  ) -> EventLoopFuture<Void> where Messages.Element == ResponsePayload {
    let promise = self.eventLoop.makePromise(of: Void.self)
    self.sendResponses(messages, compression: compression, promise: promise)
    return promise.futureResult
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
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    let response = _MessageContext(
      message,
      compressed: compression.isEnabled(callDefault: self.compressionEnabled)
    )
    self.channel.writeAndFlush(self.wrap(.message(response)), promise: promise)
  }

  override open func sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where ResponsePayload == Messages.Element {
    let compress = compression.isEnabled(callDefault: self.compressionEnabled)

    var iterator = messages.makeIterator()
    var next = iterator.next()

    while let current = next {
      next = iterator.next()
      // Attach the promise, if present, to the last message.
      let isLast = next == nil
      self.channel.write(
        self.wrap(.message(.init(current, compressed: compress))),
        promise: isLast ? promise : nil
      )
    }

    self.channel.flush()
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used for testing.
///
/// Simply records all sent messages.
open class StreamingResponseCallContextTestStub<ResponsePayload>: StreamingResponseCallContext<ResponsePayload> {
  open var recordedResponses: [ResponsePayload] = []

  override open func sendResponse(
    _ message: ResponsePayload,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    self.recordedResponses.append(message)
    promise?.succeed(())
  }

  override open func sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where ResponsePayload == Messages.Element {
    self.recordedResponses.append(contentsOf: messages)
    promise?.succeed(())
  }
}
