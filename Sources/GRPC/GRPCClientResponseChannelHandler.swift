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
import SwiftProtobuf
import NIO
import NIOHPACK
import Logging

/// A base channel handler for receiving responses.
///
/// This includes holding promises for the initial metadata and status of the gRPC call. This handler
/// is also responsible for error handling, via an error delegate and by appropriately failing the
/// aforementioned promises.
internal class GRPCClientResponseChannelHandler<ResponsePayload: GRPCPayload>: ChannelInboundHandler {
  public typealias InboundIn = _GRPCClientResponsePart<ResponsePayload>
  internal let logger: Logger
  internal var stopwatch: Stopwatch?

  internal let initialMetadataPromise: EventLoopPromise<HPACKHeaders>
  internal let trailingMetadataPromise: EventLoopPromise<HPACKHeaders>
  internal let statusPromise: EventLoopPromise<GRPCStatus>

  internal let timeout: GRPCTimeout
  internal var timeoutTask: Scheduled<Void>?
  internal let errorDelegate: ClientErrorDelegate?

  internal var context: ChannelHandlerContext?

  /// Creates a new `ClientResponseChannelHandler`.
  ///
  /// - Parameters:
  ///   - initialMetadataPromise: A promise to succeed on receiving the initial metadata from the service.
  ///   - trailingMetadataPromise: A promise to succeed on receiving the trailing metadata from the service.
  ///   - statusPromise: A promise to succeed with the outcome of the call.
  ///   - errorDelegate: An error delegate to call when errors are observed.
  ///   - timeout: The call timeout specified by the user.
  public init(
    initialMetadataPromise: EventLoopPromise<HPACKHeaders>,
    trailingMetadataPromise: EventLoopPromise<HPACKHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout,
    logger: Logger
  ) {
    self.initialMetadataPromise = initialMetadataPromise
    self.trailingMetadataPromise = trailingMetadataPromise
    self.statusPromise = statusPromise
    self.errorDelegate = errorDelegate
    self.timeout = timeout
    self.logger = logger
  }

  /// Observe the given status.
  ///
  /// The `status` promise is __succeeded__ with the given status despite `GRPCStatus` conforming to
  /// `Error`. If `status.code != .ok` then the initial metadata and response promises (if applicable)
  /// are failed with the given status.
  ///
  /// - Parameter status: the status to observe.
  internal func onStatus(_ status: GRPCStatus) {
    if status.code != .ok {
      self.initialMetadataPromise.fail(status)
    }
    self.trailingMetadataPromise.fail(status)
    self.statusPromise.succeed(status)
    self.timeoutTask?.cancel()
    self.context = nil

    if let stopwatch = self.stopwatch {
      let millis = stopwatch.elapsedMillis()
      self.logger.debug("rpc call finished", metadata: [
        "duration_ms": "\(millis)",
        "status_code": "\(status.code.rawValue)"
      ])
      self.stopwatch = nil
    }
  }

  /// Observe the given error.
  ///
  /// If an `errorDelegate` has been set, the delegate's `didCatchError(error:logger:file:line:)` method is
  /// called with the wrapped error and its source. Any unfulfilled promises are also resolved with
  /// the given error (see `observeStatus(_:)`).
  ///
  /// - Parameter error: the error to observe.
  internal func onError(_ error: Error) {
    if let errorWithContext = error as? GRPCError.WithContext {
      self.errorDelegate?.didCatchError(
          errorWithContext.error,
          logger: self.logger,
          file: errorWithContext.file,
          line: errorWithContext.line
      )
      self.onStatus(errorWithContext.error.makeGRPCStatus())
    } else {
      self.errorDelegate?.didCatchErrorWithoutContext(error, logger: self.logger)
      self.onStatus((error as? GRPCStatusTransformable)?.makeGRPCStatus() ?? .processingError)
    }
  }

  /// Called when a response is received. Subclasses should override this method.
  ///
  /// - Parameter response: The received response.
  internal func onResponse(_ response: _MessageContext<ResponsePayload>) {
    // no-op
  }

  public func handlerAdded(context: ChannelHandlerContext) {
    // We need to hold the context in case we timeout and need to close the pipeline.
    self.context = context
    self.stopwatch = .start()
  }

  /// Reads inbound data.
  ///
  /// On receipt of:
  /// - headers: the initial metadata promise is succeeded.
  /// - message: `onResponse(_:)` is called with the received message.
  /// - status: the status promise is succeeded; if the status is not `ok` then the initial metadata
  ///   and response promise (if available) are failed with the status.
  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .initialMetadata(let headers):
      self.initialMetadataPromise.succeed(headers)

    case .message(let message):
      self.onResponse(message)

    case .trailingMetadata(let trailers):
      self.trailingMetadataPromise.succeed(trailers)

    case let .status(status):
      self.onStatus(status)
      // We don't expect any more requests/responses beyond this point and we don't need to close
      // the channel since NIO's HTTP/2 channel handlers will deal with this for us.
    }
  }

  public func channelInactive(context: ChannelHandlerContext) {
    self.onStatus(.init(code: .unavailable, message: nil))
    context.fireChannelInactive()
  }

  /// Observe an error from the pipeline and close the channel.
  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.onError(error)
    context.close(mode: .all, promise: nil)
  }

  /// Schedules a timeout on the given event loop if the timeout is not `.infinite`.
  /// - Parameter eventLoop: The `eventLoop` to schedule the timeout on.
  internal func scheduleTimeout(eventLoop: EventLoop) {
    guard self.timeout != .infinite else {
      return
    }

    let timeout = self.timeout
    self.timeoutTask = eventLoop.scheduleTask(in: timeout.asNIOTimeAmount) { [weak self] in
      self?.performTimeout(error: GRPCError.RPCTimedOut(timeout).captureContext())
    }
  }

  /// Called when this call times out. Any promises which have not been fulfilled will be timed out
  /// with status `.deadlineExceeded`. If this handler has a context associated with it then the
  /// its channel is closed.
  ///
  /// - Parameter error: The error to fail any promises with.
  internal func performTimeout(error: GRPCError.WithContext) {
    self.onError(error)
    self.context?.close(mode: .all, promise: nil)
    self.context = nil
  }
}

/// A channel handler for client calls which receive a single response.
final class GRPCClientUnaryResponseChannelHandler<ResponsePayload: GRPCPayload>: GRPCClientResponseChannelHandler<ResponsePayload> {
  let responsePromise: EventLoopPromise<ResponsePayload>

  internal init(
    initialMetadataPromise: EventLoopPromise<HPACKHeaders>,
    trailingMetadataPromise: EventLoopPromise<HPACKHeaders>,
    responsePromise: EventLoopPromise<ResponsePayload>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout,
    logger: Logger
  ) {
    self.responsePromise = responsePromise

    super.init(
      initialMetadataPromise: initialMetadataPromise,
      trailingMetadataPromise: trailingMetadataPromise,
      statusPromise: statusPromise,
      errorDelegate: errorDelegate,
      timeout: timeout,
      logger: logger
    )
  }

  /// Succeeds the response promise with the given response.
  ///
  /// - Parameter response: The response received from the service.
  override func onResponse(_ response: _MessageContext<ResponsePayload>) {
    self.responsePromise.succeed(response.message)
  }

  /// Fails the response promise if the given status is not `.ok`.
  override func onStatus(_ status: GRPCStatus) {
    super.onStatus(status)

    if status.code != .ok {
      self.responsePromise.fail(status)
    }
  }

  // Workaround for SR-11564 (observed in Xcode 11.2 Beta).
  // See: https://bugs.swift.org/browse/SR-11564
  //
  // TODO: Remove this once SR-11564 is resolved.
  override internal func scheduleTimeout(eventLoop: EventLoop) {
    super.scheduleTimeout(eventLoop: eventLoop)
  }
}

/// A channel handler for client calls which receive a stream of responses.
final class GRPCClientStreamingResponseChannelHandler<ResponsePayload: GRPCPayload>: GRPCClientResponseChannelHandler<ResponsePayload> {
  typealias ResponseHandler = (ResponsePayload) -> Void

  let responseHandler: ResponseHandler

  internal init(
    initialMetadataPromise: EventLoopPromise<HPACKHeaders>,
    trailingMetadataPromise: EventLoopPromise<HPACKHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout,
    logger: Logger,
    responseHandler: @escaping ResponseHandler
  ) {
    self.responseHandler = responseHandler

    super.init(
      initialMetadataPromise: initialMetadataPromise,
      trailingMetadataPromise: trailingMetadataPromise,
      statusPromise: statusPromise,
      errorDelegate: errorDelegate,
      timeout: timeout,
      logger: logger
    )
  }

  /// Calls a user-provided handler with the given response.
  ///
  /// - Parameter response: The response received from the service.
  override func onResponse(_ response: _MessageContext<ResponsePayload>) {
    self.responseHandler(response.message)
  }

  // Workaround for SR-11564 (observed in Xcode 11.2 Beta).
  // See: https://bugs.swift.org/browse/SR-11564
  //
  // TODO: Remove this once SR-11564 is resolved.
  override internal func scheduleTimeout(eventLoop: EventLoop) {
    super.scheduleTimeout(eventLoop: eventLoop)
  }
}

/// Client user events.
internal enum GRPCClientUserEvent {
  /// The call has been cancelled.
  case cancelled
}
