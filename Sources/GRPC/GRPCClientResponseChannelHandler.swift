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
import NIOHTTP1

/// A base channel handler for receiving responses.
///
/// This includes hold promises for the initial metadata and status of the gRPC call. This handler
/// is also responsible for error handling, via an error delegate and by appropriately failing the
/// aforementioned promises.
internal class GRPCClientResponseChannelHandler<ResponseMessage: Message>: ChannelInboundHandler {
  public typealias InboundIn = GRPCClientResponsePart<ResponseMessage>

  internal let initialMetadataPromise: EventLoopPromise<HTTPHeaders>
  internal let statusPromise: EventLoopPromise<GRPCStatus>

  internal let timeout: GRPCTimeout
  internal var timeoutTask: Scheduled<Void>?
  internal let errorDelegate: ClientErrorDelegate?

  internal enum InboundState {
    case expectingHeadersOrStatus
    case expectingMessageOrStatus
    case expectingStatus
    case ignore

    var expectingStatus: Bool {
      switch self {
      case .expectingHeadersOrStatus, .expectingMessageOrStatus, .expectingStatus:
        return true

      case .ignore:
        return false
      }
    }
  }

  /// The arity of a response.
  internal enum ResponseArity {
    case one
    case many

    /// The inbound state after receiving a response.
    var inboundStateAfterResponse: InboundState {
      switch self {
      case .one:
        return .expectingStatus
      case .many:
        return .expectingMessageOrStatus
      }
    }
  }

  private let responseArity: ResponseArity
  private var inboundState: InboundState = .expectingHeadersOrStatus

  /// Creates a new `GRPCClientResponseChannelHandler`.
  ///
  /// - Parameters:
  ///   - initialMetadataPromise: A promise to succeed on receiving the initial metadata from the service.
  ///   - statusPromise: A promise to succeed with the outcome of the call.
  ///   - errorDelegate: An error delegate to call when errors are observed.
  ///   - timeout: The call timeout specified by the user.
  ///   - expectedResponses: The number of responses expected.
  public init(
    initialMetadataPromise: EventLoopPromise<HTTPHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout,
    expectedResponses: ResponseArity
  ) {
    self.initialMetadataPromise = initialMetadataPromise
    self.statusPromise = statusPromise
    self.errorDelegate = errorDelegate
    self.timeout = timeout
    self.responseArity = expectedResponses
  }

  /// Observe the given status.
  ///
  /// The `status` promise is __succeeded__ with the given status despite `GRPCStatus` conforming to
  /// `Error`. If `status.code != .ok` then the initial metadata and response promises (if applicable)
  /// are failed with the given status.
  ///
  /// - Parameter status: the status to observe.
  internal func observeStatus(_ status: GRPCStatus) {
    if status.code != .ok {
      self.initialMetadataPromise.fail(status)
    }
    self.statusPromise.succeed(status)
    self.timeoutTask?.cancel()
  }

  /// Observe the given error.
  ///
  /// If an `errorDelegate` has been set, the delegate's `didCatchError(error:file:line:)` method is
  /// called with the wrapped error and its source. Any unfulfilled promises are also resolved with
  /// the given error (see `observeStatus(_:)`).
  ///
  /// - Parameter error: the error to observe.
  internal func observeError(_ error: GRPCError) {
    self.errorDelegate?.didCatchError(error.wrappedError, file: error.file, line: error.line)
    self.observeStatus(error.asGRPCStatus())
  }

  /// Called when a response is received. Subclasses should override this method.
  ///
  /// - Parameter response: The received response.
  internal func onResponse(_ response: _Box<ResponseMessage>) {
    // no-op
  }

  /// Reads inbound data.
  ///
  /// On receipt of:
  /// - headers: the initial metadata promise is succeeded.
  /// - message: `onResponse(_:)` is called with the received message.
  /// - status: the status promise is succeeded; if the status is not `ok` then the initial metadata
  ///   and response promise (if available) are failed with the status.
  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    guard self.inboundState != .ignore else { return }

    switch self.unwrapInboundIn(data) {
    case .headers(let headers):
      guard self.inboundState == .expectingHeadersOrStatus else {
        self.errorCaught(context: context, error: GRPCError.client(.invalidState("received headers while in state \(self.inboundState)")))
        return
      }

      self.initialMetadataPromise.succeed(headers)
      self.inboundState = .expectingMessageOrStatus

    case .message(let boxedMessage):
      guard self.inboundState == .expectingMessageOrStatus else {
        self.errorCaught(context: context, error: GRPCError.client(.responseCardinalityViolation))
        return
      }

      self.onResponse(boxedMessage)
      self.inboundState = self.responseArity.inboundStateAfterResponse

    case .status(let status):
      guard self.inboundState.expectingStatus else {
        self.errorCaught(context: context, error: GRPCError.client(.invalidState("received status while in state \(self.inboundState)")))
        return
      }

      self.observeStatus(status)
      // We don't expect any more requests/responses beyond this point and we don't need to close
      // the channel since NIO's HTTP/2 channel handlers will deal with this for us.
    }
  }

  public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
    if let clientUserEvent = event as? GRPCClientUserEvent {
      switch clientUserEvent {
      case .cancelled:
        // We shouldn't observe an error since this event is triggered by the user: just observe the
        // status.
        self.observeStatus(GRPCError.client(.cancelledByClient).asGRPCStatus())
        context.close(promise: nil)
      }
    }
  }

  public func channelActive(context: ChannelHandlerContext) {
    if self.timeout != .infinite {
      let timeout = self.timeout
      self.timeoutTask = context.eventLoop.scheduleTask(in: timeout.asNIOTimeAmount) { [weak self] in
        self?.errorCaught(context: context, error: GRPCError.client(.deadlineExceeded(timeout)))
      }
    }
  }

  public func channelInactive(context: ChannelHandlerContext) {
    self.inboundState = .ignore
    self.observeStatus(.init(code: .unavailable, message: nil))
    context.fireChannelInactive()
  }

  /// Observe an error from the pipeline and close the channel.
  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.observeError((error as? GRPCError) ?? GRPCError.unknown(error, origin: .client))
    context.close(mode: .all, promise: nil)
  }
}

/// A channel handler for client calls which recieve a single response.
final class GRPCClientUnaryResponseChannelHandler<ResponseMessage: Message>: GRPCClientResponseChannelHandler<ResponseMessage> {
  let responsePromise: EventLoopPromise<ResponseMessage>

  internal init(
    initialMetadataPromise: EventLoopPromise<HTTPHeaders>,
    responsePromise: EventLoopPromise<ResponseMessage>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout
  ) {
    self.responsePromise = responsePromise

    super.init(
      initialMetadataPromise: initialMetadataPromise,
      statusPromise: statusPromise,
      errorDelegate: errorDelegate,
      timeout: timeout,
      expectedResponses: .one
    )
  }

  /// Succeeds the response promise with the given response.
  ///
  /// - Parameter response: The response received from the service.
  override func onResponse(_ response: _Box<ResponseMessage>) {
    self.responsePromise.succeed(response.value)
  }

  /// Fails the response promise if the given status is not `.ok`.
  override func observeStatus(_ status: GRPCStatus) {
    super.observeStatus(status)

    if status.code != .ok {
      self.responsePromise.fail(status)
    }
  }
}

/// A channel handler for client calls which recieve a stream of responses.
final class GRPCClientStreamingResponseChannelHandler<ResponseMessage: Message>: GRPCClientResponseChannelHandler<ResponseMessage> {
  typealias ResponseHandler = (ResponseMessage) -> Void

  let responseHandler: ResponseHandler

  internal init(
    initialMetadataPromise: EventLoopPromise<HTTPHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    errorDelegate: ClientErrorDelegate?,
    timeout: GRPCTimeout,
    responseHandler: @escaping ResponseHandler
  ) {
    self.responseHandler = responseHandler

    super.init(
      initialMetadataPromise: initialMetadataPromise,
      statusPromise: statusPromise,
      errorDelegate: errorDelegate,
      timeout: timeout,
      expectedResponses: .many
    )
  }

  /// Calls a user-provided handler with the given response.
  ///
  /// - Parameter response: The response received from the service.
  override func onResponse(_ response: _Box<ResponseMessage>) {
    self.responseHandler(response.value)
  }
}

/// Client user events.
public enum GRPCClientUserEvent {
  /// The call has been cancelled.
  case cancelled
}
