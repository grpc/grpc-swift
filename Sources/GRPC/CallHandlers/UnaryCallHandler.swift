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

/// Handles unary calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and returns a future containing the call result.
/// - To return a response to the client, the framework user should complete that future
///   (similar to e.g. serving regular HTTP requests in frameworks such as Vapor).
public final class UnaryCallHandler<
  RequestDeserializer: MessageDeserializer,
  ResponseSerializer: MessageSerializer
>: _BaseCallHandler<RequestDeserializer, ResponseSerializer> {
  @usableFromInline
  internal typealias _Context = UnaryResponseCallContext<ResponsePayload>
  @usableFromInline
  internal typealias _Observer = (RequestPayload) -> EventLoopFuture<ResponsePayload>

  @usableFromInline
  internal var _callHandlerState: _CallHandlerState

  @usableFromInline
  internal enum _CallHandlerState {
    // We don't have the following states (which we do have in the main state machine):
    // - 'requestOpenResponseIdle',
    // - 'requestClosedResponseIdle'
    //
    // We'll send headers back when we transition away from 'requestIdleResponseIdle' so the
    // response stream can never be less idle than the request stream.

    /// Fully idle, we haven't seen the request headers yet and we haven't made an event observer
    /// yet.
    case requestIdleResponseIdle((_Context) -> _Observer)

    /// Received the request headers, created an observer and have sent back response headers.
    /// We may or may not have observer the request message yet.
    case requestOpenResponseOpen(_Context, ObserverState)

    /// Received the request headers, a message and the end of the request stream. The observer has
    /// been invoked but it hasn't yet finished processing the request.
    ///
    /// Note: we know we've received a message if we're in this state, if we had seen the request
    /// headers followed by end we'd fully close.
    case requestClosedResponseOpen(_Context)

    /// We're done.
    case requestClosedResponseClosed

    /// The state of the event observer.
    @usableFromInline
    enum ObserverState {
      /// We have an event observer, but haven't yet received a request.
      case notObserved(_Observer)
      /// We've invoked the event observer with a request.
      case observed
    }
  }

  @inlinable
  internal init(
    serializer: ResponseSerializer,
    deserializer: RequestDeserializer,
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<RequestDeserializer.Output, ResponseSerializer.Input>],
    eventObserverFactory: @escaping (UnaryResponseCallContext<ResponsePayload>)
      -> (RequestPayload) -> EventLoopFuture<ResponsePayload>
  ) {
    self._callHandlerState = .requestIdleResponseIdle(eventObserverFactory)
    super.init(
      callHandlerContext: callHandlerContext,
      requestDeserializer: deserializer,
      responseSerializer: serializer,
      callType: .unary,
      interceptors: interceptors
    )
  }

  override public func channelInactive(context: ChannelHandlerContext) {
    super.channelInactive(context: context)

    // Fail any remaining promise.
    switch self._callHandlerState {
    case .requestIdleResponseIdle,
         .requestClosedResponseClosed:
      self._callHandlerState = .requestClosedResponseClosed

    case let .requestOpenResponseOpen(context, _),
         let .requestClosedResponseOpen(context):
      self._callHandlerState = .requestClosedResponseClosed
      context.responsePromise.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Handle an error from the event observer.
  private func handleObserverError(_ error: Error) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: request observer hasn't been created")

    case let .requestOpenResponseOpen(context, _),
         let .requestClosedResponseOpen(context):
      let (status, trailers) = self.processObserverError(
        error,
        headers: context.headers,
        trailers: context.trailers
      )
      // This will handle the response promise as well.
      self.sendEnd(status: status, trailers: trailers)

    case .requestClosedResponseClosed:
      // We hit an error, but we're already closed (i.e. we hit a library error first). Ignore
      // the error.
      ()
    }
  }

  /// Handle a 'library' error, i.e. an error emanating from the `Channel`.
  private func handleLibraryError(_ error: Error) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle,
         .requestOpenResponseOpen(_, .notObserved):
      // We haven't seen a message, we'll send end to close the stream.
      let (status, trailers) = self.processLibraryError(error)
      self.sendEnd(status: status, trailers: trailers)

    case .requestOpenResponseOpen(_, .observed),
         .requestClosedResponseOpen:
      // We've seen a message, the observer is in flight, we'll let it play out.
      ()

    case .requestClosedResponseClosed:
      // We're already closed, we can just ignore this.
      ()
    }
  }

  // MARK: - Inbound

  override internal func observeLibraryError(_ error: Error) {
    self.handleLibraryError(error)
  }

  override internal func observeHeaders(_ headers: HPACKHeaders) {
    switch self._callHandlerState {
    case let .requestIdleResponseIdle(factory):
      // This allocates a promise, but the observer is provided with 'StatusOnlyCallContext' and
      // doesn't get access to the promise. The observer must return a response future instead
      // which we cascade to this promise. We can avoid this extra allocation by using a different
      // context here.
      //
      // TODO: provide a new context without a promise.
      let context = UnaryResponseCallContext<ResponsePayload>(
        eventLoop: self.eventLoop,
        headers: headers,
        logger: self.logger,
        userInfoRef: self._userInfoRef
      )
      let observer = factory(context)

      // We're fully open now (we'll send the response headers back in a moment).
      self._callHandlerState = .requestOpenResponseOpen(context, .notObserved(observer))

      // Register callbacks for the response promise.
      context.responsePromise.futureResult.whenComplete { result in
        switch result {
        case let .success(response):
          self.sendResponse(response)
        case let .failure(error):
          self.handleObserverError(error)
        }
      }

      // Write back the response headers.
      self.sendResponsePartFromObserver(.metadata([:]), promise: nil)

    // The main state machine guards against these states.
    case .requestOpenResponseOpen,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: request headers already received")
    }
  }

  override internal func observeRequest(_ message: RequestPayload) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: request received before headers")

    case let .requestOpenResponseOpen(context, request):
      switch request {
      case .observed:
        // We've already observed the request message. The main state machine doesn't guard against
        // too many messages for unary streams. Assuming downstream handlers protect against this
        // then this must be an errant interceptor, we'll ignore it.
        ()

      case let .notObserved(observer):
        self._callHandlerState = .requestOpenResponseOpen(context, .observed)
        // Complete the promise with the observer block.
        context.responsePromise.completeWith(observer(message))
      }

    case .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: the request stream has already been closed")
    }
  }

  override internal func observeEnd() {
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: no request headers received")

    case let .requestOpenResponseOpen(context, request):
      switch request {
      case .observed:
        // Close the request stream.
        self._callHandlerState = .requestClosedResponseOpen(context)

      case .notObserved:
        // We haven't received a request: this is an empty stream, the observer will never be
        // invoked.
        context.responsePromise.fail(GRPCError.StreamCardinalityViolation.request)
      }

    case .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: request stream is already closed")
    }
  }

  // MARK: - Outbound

  private func sendResponse(_ message: ResponsePayload) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: can't send response before receiving headers and request")

    case .requestOpenResponseOpen(_, .notObserved):
      preconditionFailure("Invalid state: can't send response before receiving request")

    case let .requestOpenResponseOpen(context, .observed),
         let .requestClosedResponseOpen(context):
      self._callHandlerState = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(
        .message(message, .init(compress: context.compressionEnabled, flush: false)),
        promise: nil
      )
      self.sendResponsePartFromObserver(
        .end(context.responseStatus, context.trailers),
        promise: nil
      )

    case .requestClosedResponseClosed:
      // Already closed, do nothing.
      ()
    }
  }

  private func sendEnd(status: GRPCStatus, trailers: HPACKHeaders) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle,
         .requestClosedResponseOpen:
      self._callHandlerState = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(.end(status, trailers), promise: nil)

    case let .requestOpenResponseOpen(context, _):
      self._callHandlerState = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(.end(status, trailers), promise: nil)
      // Fail the promise.
      context.responsePromise.fail(status)

    case .requestClosedResponseClosed:
      // Already closed, do nothing.
      ()
    }
  }
}
