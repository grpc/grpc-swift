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

/// Handles client-streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and fulfills `context.responsePromise` when done.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the response, complete `context.responsePromise`.
public final class ClientStreamingCallHandler<
  RequestDeserializer: MessageDeserializer,
  ResponseSerializer: MessageSerializer
>: _BaseCallHandler<RequestDeserializer, ResponseSerializer> {
  private typealias Context = UnaryResponseCallContext<ResponsePayload>
  private typealias Observer = EventLoopFuture<(StreamEvent<RequestPayload>) -> Void>

  private var state: State

  // See 'UnaryCallHandler.State'.
  private enum State {
    case requestIdleResponseIdle((Context) -> Observer)
    case requestOpenResponseOpen(Context, Observer)
    case requestClosedResponseOpen(Context)
    case requestClosedResponseClosed
  }

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  internal init(
    serializer: ResponseSerializer,
    deserializer: RequestDeserializer,
    callHandlerContext: CallHandlerContext,
    interceptors: [ServerInterceptor<RequestDeserializer.Output, ResponseSerializer.Input>],
    eventObserverFactory: @escaping (UnaryResponseCallContext<ResponsePayload>)
      -> EventLoopFuture<(StreamEvent<RequestPayload>) -> Void>
  ) {
    self.state = .requestIdleResponseIdle(eventObserverFactory)
    super.init(
      callHandlerContext: callHandlerContext,
      requestDeserializer: deserializer,
      responseSerializer: serializer,
      callType: .clientStreaming,
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
      context.responsePromise.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Handle an error from the event observer.
  private func handleObserverError(_ error: Error) {
    switch self.state {
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
    switch self.state {
    case .requestIdleResponseIdle,
         .requestOpenResponseOpen:
      // We'll never see a request message, so just send end.
      let (status, trailers) = self.processLibraryError(error)
      self.sendEnd(status: status, trailers: trailers)

    case .requestClosedResponseOpen:
      // We've invoked the observer and have seen the end of the request stream. We'll let that
      // play out.
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
      let context = UnaryResponseCallContext<ResponsePayload>(
        eventLoop: self.eventLoop,
        headers: headers,
        logger: self.logger,
        userInfoRef: self.userInfoRef
      )

      let observer = factory(context)

      // Fully open. We'll send the response headers back in a moment.
      self.state = .requestOpenResponseOpen(context, observer)

      // Register a failure callback for the observer failing.
      observer.whenFailure(self.handleObserverError(_:))

      // Register callbacks on the response promise.
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

    // The main state machine guards against this.
    case .requestOpenResponseOpen,
         .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: request headers already received")
    }
  }

  override internal func observeRequest(_ message: RequestPayload) {
    switch self.state {
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
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: no request headers received")

    case let .requestOpenResponseOpen(context, observer):
      self.state = .requestClosedResponseOpen(context)
      observer.whenSuccess {
        $0(.end)
      }

    case .requestClosedResponseOpen,
         .requestClosedResponseClosed:
      preconditionFailure("Invalid state: request stream is already closed")
    }
  }

  // MARK: - Outbound

  private func sendResponse(_ message: ResponsePayload) {
    switch self.state {
    case .requestIdleResponseIdle:
      preconditionFailure("Invalid state: can't send response before receiving headers and request")

    case let .requestOpenResponseOpen(context, _),
         let .requestClosedResponseOpen(context):
      self.state = .requestClosedResponseClosed
      self.sendResponsePartFromObserver(
        .message(message, .init(compress: context.compressionEnabled, flush: false)),
        promise: nil
      )
      self.sendResponsePartFromObserver(
        .end(context.responseStatus, context.trailers),
        promise: nil
      )

    case .requestClosedResponseClosed:
      // We're already closed. This isn't a precondition failure because we may have encountered
      // an error before the observer block completed.
      ()
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
      context.responsePromise.fail(status)

    case .requestClosedResponseClosed:
      // Already closed, do nothing.
      ()
    }
  }
}
