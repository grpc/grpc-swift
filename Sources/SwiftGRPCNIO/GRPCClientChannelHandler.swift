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
/// This handler holds promises for the initial metadata and status, as well as an observer
/// for responses. For unary and client-streaming calls the observer will succeed a response
/// promise. For server-streaming and bidirectional-streaming the observer will call the supplied
/// callback with each response received.
///
/// Errors are also handled by the channel handler. Promises for the initial metadata and
/// response (if applicable) are failed with first error received. The status promise is __succeeded__
/// with the error as a `GRPCStatus`. The stream is also closed and any inbound or outbound messages
/// are ignored.
public class GRPCClientChannelHandler<RequestMessage: Message, ResponseMessage: Message> {
  internal let initialMetadataPromise: EventLoopPromise<HTTPHeaders>
  internal let statusPromise: EventLoopPromise<GRPCStatus>
  internal let responseObserver: ResponseObserver<ResponseMessage>

  /// A promise for a unary response.
  internal var responsePromise: EventLoopPromise<ResponseMessage>? {
    guard case .succeedPromise(let promise) = responseObserver else { return nil }
    return promise
  }

  /// Promise that the `HTTPRequestHead` has been sent to the network.
  ///
  /// If we attempt to close the stream before this has been fulfilled then the program will fatal
  /// error because of an issue with nghttp2/swift-nio-http2.
  ///
  /// Since we need this promise to succeed before we can close the channel, `BaseClientCall` sends
  /// the request head in `init` which will in turn initialize this promise in `write(ctx:data:promise:)`.
  ///
  /// See: https://github.com/apple/swift-nio-http2/issues/39.
  private var requestHeadSentPromise: EventLoopPromise<Void>!

  private enum InboundState {
    case expectingHeaders
    case expectingMessageOrStatus
    case ignore
  }

  private enum OutboundState {
    case expectingHead
    case expectingMessageOrEnd
    case ignore
  }

  private var inboundState: InboundState = .expectingHeaders
  private var outboundState: OutboundState = .expectingHead

  /// Creates a new `GRPCClientChannelHandler`.
  ///
  /// - Parameters:
  ///   - initialMetadataPromise: a promise to succeed on receiving the initial metadata from the service.
  ///   - statusPromise: a promise to succeed with the outcome of the call.
  ///   - responseObserver: an observer for response messages from the server; for unary responses this should
  ///     be the `succeedPromise` case.
  internal init(
    initialMetadataPromise: EventLoopPromise<HTTPHeaders>,
    statusPromise: EventLoopPromise<GRPCStatus>,
    responseObserver: ResponseObserver<ResponseMessage>
  ) {
    self.initialMetadataPromise = initialMetadataPromise
    self.statusPromise = statusPromise
    self.responseObserver = responseObserver
  }

  /// Observe the given status.
  ///
  /// The `status` promise is __succeeded__ with the given status despite `GRPCStatus` being an
  /// `Error`. If `status.code != .ok` then the initial metadata and response promises (if applicable)
  /// are failed with the given status.
  ///
  /// - Parameter status: the status to observe.
  internal func observeStatus(_ status: GRPCStatus) {
    if status.code != .ok {
      self.initialMetadataPromise.fail(error: status)
      self.responsePromise?.fail(error: status)
    }
    self.statusPromise.succeed(result: status)
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
  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    guard self.inboundState != .ignore else { return }

    switch unwrapInboundIn(data) {
    case .headers(let headers):
      guard self.inboundState == .expectingHeaders else {
        self.errorCaught(ctx: ctx, error: GRPCStatus.processingError)
        return
      }

      self.initialMetadataPromise.succeed(result: headers)
      self.inboundState = .expectingMessageOrStatus

    case .message(let message):
      guard self.inboundState == .expectingMessageOrStatus else {
        self.errorCaught(ctx: ctx, error: GRPCStatus.processingError)
        return
      }

      self.responseObserver.observe(message)

    case .status(let status):
      guard self.inboundState == .expectingMessageOrStatus else {
        self.errorCaught(ctx: ctx, error: GRPCStatus.processingError)
        return
      }

      self.observeStatus(status)

      // We don't expect any more requests/responses beyond this point.
      self.close(ctx: ctx, mode: .all, promise: nil)
    }
  }
}


extension GRPCClientChannelHandler: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart<RequestMessage>
  public typealias OutboundOut = GRPCClientRequestPart<RequestMessage>

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    guard self.inboundState != .ignore else { return }

    switch unwrapOutboundIn(data) {
    case .head:
      guard self.outboundState == .expectingHead else {
        self.errorCaught(ctx: ctx, error: GRPCStatus.processingError)
        return
      }

      // See the documentation for `requestHeadSentPromise` for an explanation of this.
      self.requestHeadSentPromise = promise ?? ctx.eventLoop.newPromise()
      ctx.write(data, promise: self.requestHeadSentPromise)
      self.outboundState = .expectingMessageOrEnd

    default:
      guard self.outboundState == .expectingMessageOrEnd else {
        self.errorCaught(ctx: ctx, error: GRPCStatus.processingError)
        return
      }

      ctx.write(data, promise: promise)
    }
  }
}

extension GRPCClientChannelHandler {
  /// Closes the HTTP/2 stream. Inbound and outbound state are set to ignore.
  public func close(ctx: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
    self.observeStatus(GRPCStatus.cancelled)

    requestHeadSentPromise.futureResult.whenComplete {
      ctx.close(mode: mode, promise: promise)
    }

    self.inboundState = .ignore
    self.outboundState = .ignore
  }

  /// Observe an error from the pipeline. Errors are cast to `GRPCStatus` or `GRPCStatus.processingError`
  /// if the cast failed and promises are fulfilled with the status. The channel is also closed.
  public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
    let status = (error as? GRPCStatus) ?? .processingError
    self.observeStatus(status)

    // We don't expect any more requests/responses beyond this point.
    self.close(ctx: ctx, mode: .all, promise: nil)
  }
}
