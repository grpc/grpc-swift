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
import NIOCore
import NIOHPACK
import NIOHTTP1
import SwiftProtobuf

/// An abstract base class for a context provided to handlers for RPCs which may return multiple
/// responses, i.e. server streaming and bidirectional streaming RPCs.
open class StreamingResponseCallContext<ResponsePayload>: ServerCallContextBase {
  /// A promise for the ``GRPCStatus``, the end of the response stream. This must be completed by
  /// bidirectional streaming RPC handlers to end the RPC.
  ///
  /// Note that while this is also present for server streaming RPCs, it is not necessary to
  /// complete this promise: instead, an `EventLoopFuture<GRPCStatus>` must be returned from the
  /// handler.
  public let statusPromise: EventLoopPromise<GRPCStatus>

  @available(*, deprecated, renamed: "init(eventLoop:headers:logger:userInfo:closeFuture:)")
  public convenience init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfo: UserInfo = UserInfo()
  ) {
    self.init(
      eventLoop: eventLoop,
      headers: headers,
      logger: logger,
      userInfoRef: .init(userInfo),
      closeFuture: eventLoop.makeFailedFuture(GRPCStatus.closeFutureNotImplemented)
    )
  }

  public convenience init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfo: UserInfo = UserInfo(),
    closeFuture: EventLoopFuture<Void>
  ) {
    self.init(
      eventLoop: eventLoop,
      headers: headers,
      logger: logger,
      userInfoRef: .init(userInfo),
      closeFuture: closeFuture
    )
  }

  @inlinable
  override internal init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>,
    closeFuture: EventLoopFuture<Void>
  ) {
    self.statusPromise = eventLoop.makePromise()
    super.init(
      eventLoop: eventLoop,
      headers: headers,
      logger: logger,
      userInfoRef: userInfoRef,
      closeFuture: closeFuture
    )
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

/// A concrete implementation of `StreamingResponseCallContext` used internally.
@usableFromInline
internal final class _StreamingResponseCallContext<Request, Response>:
  StreamingResponseCallContext<Response>
{
  @usableFromInline
  internal let _sendResponse: (Response, MessageMetadata, EventLoopPromise<Void>?) -> Void

  @usableFromInline
  internal let _compressionEnabledOnServer: Bool

  @inlinable
  internal init(
    eventLoop: EventLoop,
    headers: HPACKHeaders,
    logger: Logger,
    userInfoRef: Ref<UserInfo>,
    compressionIsEnabled: Bool,
    closeFuture: EventLoopFuture<Void>,
    sendResponse: @escaping (Response, MessageMetadata, EventLoopPromise<Void>?) -> Void
  ) {
    self._sendResponse = sendResponse
    self._compressionEnabledOnServer = compressionIsEnabled
    super.init(
      eventLoop: eventLoop,
      headers: headers,
      logger: logger,
      userInfoRef: userInfoRef,
      closeFuture: closeFuture
    )
  }

  @inlinable
  internal func shouldCompress(_ compression: Compression) -> Bool {
    guard self._compressionEnabledOnServer else {
      return false
    }
    return compression.isEnabled(callDefault: self.compressionEnabled)
  }

  @inlinable
  override func sendResponse(
    _ message: Response,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) {
    if self.eventLoop.inEventLoop {
      let compress = self.shouldCompress(compression)
      self._sendResponse(message, .init(compress: compress, flush: true), promise)
    } else {
      self.eventLoop.execute {
        let compress = self.shouldCompress(compression)
        self._sendResponse(message, .init(compress: compress, flush: true), promise)
      }
    }
  }

  @inlinable
  override func sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression = .deferToCallDefault,
    promise: EventLoopPromise<Void>?
  ) where Response == Messages.Element {
    if self.eventLoop.inEventLoop {
      self._sendResponses(messages, compression: compression, promise: promise)
    } else {
      self.eventLoop.execute {
        self._sendResponses(messages, compression: compression, promise: promise)
      }
    }
  }

  @inlinable
  internal func _sendResponses<Messages: Sequence>(
    _ messages: Messages,
    compression: Compression,
    promise: EventLoopPromise<Void>?
  ) where Response == Messages.Element {
    let compress = self.shouldCompress(compression)
    var iterator = messages.makeIterator()
    var next = iterator.next()

    while let current = next {
      next = iterator.next()
      // Attach the promise, if present, to the last message.
      let isLast = next == nil
      self._sendResponse(current, .init(compress: compress, flush: isLast), isLast ? promise : nil)
    }
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used for testing.
///
/// Simply records all sent messages.
open class StreamingResponseCallContextTestStub<ResponsePayload>: StreamingResponseCallContext<
  ResponsePayload
>
{
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
