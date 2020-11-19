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

/// Handles server-streaming calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
/// - To close the call and send the status, complete the status future returned by the observer block.
public final class ServerStreamingCallHandler<
  RequestDeserializer: MessageDeserializer,
  ResponseSerializer: MessageSerializer
>: _BaseCallHandler<RequestDeserializer, ResponseSerializer> {
  private typealias Context = StreamingResponseCallContext<ResponsePayload>
  private typealias Observer = (RequestPayload) -> EventLoopFuture<GRPCStatus>

  private var state: State

  // See 'UnaryCallHandler.State'.
  private enum State {
    case requestIdleResponseIdle((Context) -> Observer)
    case requestOpenResponseOpen(Context, ObserverState)
    case requestClosedResponseOpen(Context)
    case requestClosedResponseClosed

    enum ObserverState {
      case notObserved(Observer)
      case observed
    }
  }

  internal init(
    serializer: ResponseSerializer,
    deserializer: RequestDeserializer,
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<RequestDeserializer.Output, ResponseSerializer.Input>],
    eventObserverFactory: @escaping (StreamingResponseCallContext<ResponsePayload>)
      -> (RequestPayload) -> EventLoopFuture<GRPCStatus>
  ) {
    self.state = .requestIdleResponseIdle(eventObserverFactory)
    super.init(
      callHandlerContext: callHandlerContext,
      requestDeserializr: deserializer,
      responseSerializer: serializer,
      callType: .serverStreaming,
      interceptors: interceptors
    )
  }

  override public func channelInactive(context: ChannelHandlerContext) {
    super.channelInactive(context: context)

    // Fail any remaining promise.
    switch self.state {
    case .requestIdleResponseIdle,
         .requestClosedResponseClosed:
      self.state = .requestClosedResponseClosed

    case let .requestOpenResponseOpen(context, _),
         let .requestClosedResponseOpen(context):
      self.state = .requestClosedResponseClosed
      context.statusPromise.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Handle an error from the event observer.
  private func handleObserverError(_ error: Error) {
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: request observer hasn't been created")

    case .requestOpenResponseOpen(_, .notObserved):
      preconditionFailure("Invalid state: request observer hasn't been invoked")

    case let .requestOpenResponseOpen(context, .observed),
         let .requestClosedResponseOpen(context):
      let (status, trailers) = self.processObserverError(
        error,
        headers: context.headers,
        trailers: context.trailers
      )
      // This will handle the response promise as well.
      self.sendEnd(status: status, trailers: trailers)

    case .requestClosedResponseClosed:
      // We hit an error, but we're already closed (because we hit a library error first).
      ()
    }
  }

  /// Handle a 'library' error, i.e. an error emanating from the `Channel`.
  private func handleLibraryError(_ error: Error) {
    switch self.state {
    case .requestIdleResponseIdle,
         .requestOpenResponseOpen(_, .notObserved):
      // We'll never see a request message: send end.
      let (status, trailers) = self.processLibraryError(error)
      self.sendEnd(status: status, trailers: trailers)

    case .requestOpenResponseOpen(_, .observed),
         .requestClosedResponseOpen:
      // We've invoked the observer, we expect a response. We'll let this play out.
      ()

    case .requestClosedResponseClosed:
      // We're already closed, no need to do anything here.
      ()
    }
  }

  // MARK: - Inbound

  override func observeLibraryError(_ error: Error) {
    self.handleLibraryError(error)
  }

  override internal func observeHeaders(_ headers: HPACKHeaders) {
    switch self.state {
    case let .requestIdleResponseIdle(factory):
      let context = _StreamingResponseCallContext<RequestPayload, ResponsePayload>(
        eventLoop: self.eventLoop,
        headers: headers,
        logger: self.logger,
        userInfoRef: self.userInfoRef,
        sendResponse: self.sendResponse(_:metadata:promise:)
      )
      let observer = factory(context)

      // Fully open. We'll send the response headers back in a moment.
      self.state = .requestOpenResponseOpen(context, .notObserved(observer))

      // Register callbacks for the status promise.
      context.statusPromise.futureResult.whenComplete { result in
        switch result {
        case let .success(status):
          self.sendEnd(status: status, trailers: context.trailers)
        case let .failure(error):
          self.handleObserverError(error)
        }
      }

      // Write back the response headers.
      self.sendResponsePartFromObserver(.metadata([:]), promise: nil)

    // The main state machine guards against this.
    case .requestOpenResponseOpen,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state")
    }
  }

  override internal func observeRequest(_ message: RequestPayload) {
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: request received before headers")

    case let .requestOpenResponseOpen(context, request):
      switch request {
      case .observed:
        // We've already observed the request message. The main state machine doesn't guard against
        // too many messages for unary streams. Assuming downstream handlers protect against this
        // then this must be an errant interceptor.
        ()

      case let .notObserved(observer):
        self.state = .requestOpenResponseOpen(context, .observed)
        // Complete the status promise with the observer block.
        context.statusPromise.completeWith(observer(message))
      }

    case .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: the request stream has already been closed")
    }
  }

  override internal func observeEnd() {
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: no request headers received")

    case let .requestOpenResponseOpen(context, request):
      switch request {
      case .observed:
        // Close the request stream.
        self.state = .requestClosedResponseOpen(context)

      case .notObserved:
        // We haven't received a request: this is an empty stream, the observer will never be
        // invoked. Fail the response promise (which will have no side effect).
        context.statusPromise.fail(GRPCError.StreamCardinalityViolation.request)
      }

    case .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: request stream is already closed")
    }
  }

  // MARK: - Outbound

  private func sendResponse(
    _ message: ResponsePayload,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: can't send response before receiving headers and request")

    case .requestOpenResponseOpen(_, .notObserved):
      preconditionFailure("Invalid state: can't send response before receiving request")

    case .requestOpenResponseOpen(_, .observed),
         .requestClosedResponseOpen:
      self.sendResponsePartFromObserver(.message(message, metadata), promise: promise)

    case .requestClosedResponseClosed:
      // We're already closed. This isn't a precondition failure because we may have encountered
      // an error before the observer block completed.
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  private func sendEnd(status: GRPCStatus, trailers: HPACKHeaders) {
    switch self.state {
    case .requestIdleResponseIdle,
         .requestClosedResponseOpen:
      self.state = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(.end(status, trailers), promise: nil)

    case let .requestOpenResponseOpen(context, _):
      self.state = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(.end(status, trailers), promise: nil)
      // Fail the promise.
      context.statusPromise.fail(status)

    case .requestClosedResponseClosed:
      // Already closed, do nothing.
      ()
    }
  }
}
