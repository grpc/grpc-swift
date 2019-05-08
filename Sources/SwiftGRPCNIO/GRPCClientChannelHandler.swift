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
import NIO
import NIOHTTP1
import SwiftProtobuf

/// The final client-side channel handler.
///
/// This handler holds promises for the initial metadata and the status, as well as an observer
/// for responses. For unary and client-streaming calls the observer will succeed a response
/// promise. For server-streaming and bidirectional-streaming the observer will call the supplied
/// callback with each response received.
///
/// Errors are also handled by the channel handler. Promises for the initial metadata and
/// response (if applicable) are failed with first error received. The status promise is __succeeded__
/// with the error as the result of `GRPCStatusTransformable.asGRPCStatus()`, if available.
/// The stream is also closed and any inbound or outbound messages are ignored.
internal class GRPCClientChannelHandler<RequestMessage: Message, ResponseMessage: Message> {
  internal let initialMetadataPromise: EventLoopPromise<HTTPHeaders>
  internal let statusPromise: EventLoopPromise<GRPCStatus>
  internal let responseObserver: ResponseObserver<ResponseMessage>
  internal let errorDelegate: ClientErrorDelegate?

  /// A promise for a unary response.
  internal var responsePromise: EventLoopPromise<ResponseMessage>? {
    guard case .succeedPromise(let promise) = responseObserver else { return nil }
    return promise
  }

  private enum InboundState {
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

  private enum OutboundState {
    case expectingHead
    case expectingMessageOrEnd
    case ignore
  }

  private var inboundState: InboundState = .expectingHeadersOrStatus
  private var outboundState: OutboundState = .expectingHead

  /// Creates a new `GRPCClientChannelHandler`.
  ///
  /// - Parameters:
  ///   - initialMetadataPromise: a promise to succeed on receiving the initial metadata from the service.
  ///   - statusPromise: a promise to succeed with the outcome of the call.
  ///   - responseObserver: an observer for response messages from the server; for unary responses this should
  ///     be the `succeedPromise` case.
  public init(
    initialMetadataPromise: EventLoopPromise<HTTPHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    responseObserver: ResponseObserver<ResponseMessage>,
    errorDelegate: ClientErrorDelegate?
  ) {
    self.initialMetadataPromise = initialMetadataPromise
    self.statusPromise = statusPromise
    self.responseObserver = responseObserver
    self.errorDelegate = errorDelegate
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
      self.responsePromise?.fail(status)
    }
    self.statusPromise.succeed(status)
  }

  /// Observe the given error.
  ///
  /// If an `errorDelegate` has been set, the delegate's `didCatchError(error:file:line:)` method is
  /// called with the wrapped error and its source. Any unfulfilled promises are also resolved with
  /// the given error (see `observeStatus(_:)`).
  ///
  /// - Parameter error: the error to observe.
  internal func observeError(_ error: GRPCError) {
    self.errorDelegate?.didCatchError(error.error, file: error.file, line: error.line)
    self.observeStatus(error.asGRPCStatus())
  }
}

extension GRPCClientChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = GRPCClientResponsePart<ResponseMessage>

  /// Reads inbound data.
  ///
  /// On receipt of:
  /// - headers: the initial metadata promise is succeeded.
  /// - message: the message observer is called with the message; for unary responses a response
  ///   promise is succeeded, otherwise a callback is called.
  /// - status: the status promise is succeeded; if the status is not `ok` then the initial metadata
  ///   and response promise (if available) are failed with the status. The channel is then closed.
  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    guard self.inboundState != .ignore else { return }

    switch unwrapInboundIn(data) {
    case .headers(let headers):
      guard self.inboundState == .expectingHeadersOrStatus else {
        self.errorCaught(context: context, error: GRPCError.client(.invalidState("received headers while in state \(self.inboundState)")))
        return
      }

      self.initialMetadataPromise.succeed(headers)
      self.inboundState = .expectingMessageOrStatus

    case .message(let message):
      guard self.inboundState == .expectingMessageOrStatus else {
        self.errorCaught(context: context, error: GRPCError.client(.responseCardinalityViolation))
        return
      }

      self.responseObserver.observe(message)
      self.inboundState = self.responseObserver.expectsMultipleResponses ? .expectingMessageOrStatus : .expectingStatus

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
}

extension GRPCClientChannelHandler: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart<RequestMessage>
  public typealias OutboundOut = GRPCClientRequestPart<RequestMessage>

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    guard self.outboundState != .ignore else { return }

    switch self.unwrapOutboundIn(data) {
    case .head:
      guard self.outboundState == .expectingHead else {
        self.errorCaught(context: context, error: GRPCError.client(.invalidState("received headers while in state \(self.outboundState)")))
        return
      }

      context.write(data, promise: promise)
      self.outboundState = .expectingMessageOrEnd

    default:
      guard self.outboundState == .expectingMessageOrEnd else {
        self.errorCaught(context: context, error: GRPCError.client(.invalidState("received message or end while in state \(self.outboundState)")))
        return
      }

      context.write(data, promise: promise)
    }
  }
}

extension GRPCClientChannelHandler {
  /// Closes the HTTP/2 stream. Inbound and outbound state are set to ignore.
  public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
    self.observeError(GRPCError.client(.cancelledByClient))

    context.close(mode: mode, promise: promise)

    self.inboundState = .ignore
    self.outboundState = .ignore
  }

  /// Observe an error from the pipeline and close the channel.
  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.observeError((error as? GRPCError) ?? GRPCError.unknown(error, origin: .client))
    context.close(mode: .all, promise: nil)
  }
}
