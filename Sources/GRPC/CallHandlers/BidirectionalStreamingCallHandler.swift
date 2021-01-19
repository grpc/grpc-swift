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
import SwiftProtobuf

/// Handles bidirectional streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the status, complete `context.statusPromise`.
public class BidirectionalStreamingCallHandler<
  RequestDeserializer: MessageDeserializer,
  ResponseSerializer: MessageSerializer
>: _BaseCallHandler<RequestDeserializer, ResponseSerializer> {
  @usableFromInline
  internal typealias _Context = StreamingResponseCallContext<ResponsePayload>
  @usableFromInline
  internal typealias _Observer = EventLoopFuture<(StreamEvent<RequestPayload>) -> Void>

  @usableFromInline
  internal var _callHandlerState: _CallHandlerState

  // See 'UnaryCallHandler.State'.
  @usableFromInline
  internal enum _CallHandlerState {
    case requestIdleResponseIdle((_Context) -> _Observer)
    case requestOpenResponseOpen(_Context, _Observer)
    case requestClosedResponseOpen(_Context)
    case requestClosedResponseClosed
  }

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  @inlinable
  internal init(
    serializer: ResponseSerializer,
    deserializer: RequestDeserializer,
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<RequestDeserializer.Output, ResponseSerializer.Input>],
    eventObserverFactory: @escaping (StreamingResponseCallContext<ResponsePayload>)
      -> EventLoopFuture<(StreamEvent<RequestPayload>) -> Void>
  ) {
    self._callHandlerState = .requestIdleResponseIdle(eventObserverFactory)
    super.init(
      callHandlerContext: callHandlerContext,
      requestDeserializer: deserializer,
      responseSerializer: serializer,
      callType: .bidirectionalStreaming,
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
      context.statusPromise.fail(GRPCError.AlreadyComplete())
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
      // We hit an error, but we're already closed (because we hit a library error first).
      ()
    }
  }

  /// Handle a 'library' error, i.e. an error emanating from the `Channel`.
  private func handleLibraryError(_ error: Error) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle,
         .requestOpenResponseOpen:
      // We'll never see end of stream, we'll close.
      let (status, trailers) = self.processLibraryError(error)
      self.sendEnd(status: status, trailers: trailers)

    case .requestClosedResponseOpen:
      // We've invoked the observer and seen the end of the request stream. We'll let this one play
      // out.
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
    switch self._callHandlerState {
    case let .requestIdleResponseIdle(factory):
      let context = _StreamingResponseCallContext<RequestPayload, ResponsePayload>(
        eventLoop: self.eventLoop,
        headers: headers,
        logger: self.logger,
        userInfoRef: self._userInfoRef,
        compressionIsEnabled: self._callHandlerContext.encoding.isEnabled,
        sendResponse: self.sendResponse(_:metadata:promise:)
      )
      let observer = factory(context)

      // Fully open. We'll send the response headers back in a moment.
      self._callHandlerState = .requestOpenResponseOpen(context, observer)

      // Register a failure callback for the observer failing.
      observer.whenFailure(self.handleObserverError(_:))

      // Register actions on the status promise.
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
      preconditionFailure("Invalid state: request headers already received")
    }
  }

  override internal func observeRequest(_ message: RequestPayload) {
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: request received before headers")

    case let .requestOpenResponseOpen(_, observer):
      observer.whenSuccess {
        $0(.message(message))
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

    case let .requestOpenResponseOpen(context, observer):
      self._callHandlerState = .requestClosedResponseOpen(context)
      observer.whenSuccess {
        $0(.end)
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
    switch self._callHandlerState {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: can't send response before receiving headers and request")

    case .requestOpenResponseOpen,
         .requestClosedResponseOpen:
      self.sendResponsePartFromObserver(.message(message, metadata), promise: promise)

    case .requestClosedResponseClosed:
      // We're already closed. This isn't a precondition failure because we may have encountered
      // an error before the observer block completed.
      promise?.fail(GRPCError.AlreadyComplete())
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
      context.statusPromise.fail(status)

    case .requestClosedResponseClosed:
      // Already closed, do nothing.
      ()
    }
  }
}
