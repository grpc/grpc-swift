/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Logging
import NIOCore
import NIOHPACK
import NIOHTTP2

/// A pipeline for intercepting client request and response streams.
///
/// The interceptor pipeline lies between the call object (`UnaryCall`, `ClientStreamingCall`, etc.)
/// and the transport used to send and receive messages from the server (a `NIO.Channel`). It holds
/// a collection of interceptors which may be used to observe or alter messages as the travel
/// through the pipeline.
///
/// ```
/// ┌───────────────────────────────────────────────────────────────────┐
/// │                                Call                               │
/// └────────────────────────────────────────────────────────┬──────────┘
///                                                          │ send(_:promise) /
///                                                          │ cancel(promise:)
/// ┌────────────────────────────────────────────────────────▼──────────┐
/// │                         InterceptorPipeline            ╎          │
/// │                                                        ╎          │
/// │ ┌──────────────────────────────────────────────────────▼────────┐ │
/// │ │     Tail Interceptor (hands response parts to a callback)     │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 1                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │                          Interceptor 2                        │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │          ╎                                             ╎          │
/// │          ╎              (More interceptors)            ╎          │
/// │          ╎                                             ╎          │
/// │ ┌────────┴─────────────────────────────────────────────▼────────┐ │
/// │ │          Head Interceptor (interacts with transport)          │ │
/// │ └────────▲─────────────────────────────────────────────┬────────┘ │
/// │          ╎ receive(_:)                                 │          │
/// └──────────▲─────────────────────────────────────────────┼──────────┘
///            │ receive(_:)                                 │ send(_:promise:) /
///            │                                             │ cancel(promise:)
/// ┌──────────┴─────────────────────────────────────────────▼──────────┐
/// │                           ClientTransport                         │
/// │                       (a NIO.ChannelHandler)                      │
/// ```
@usableFromInline
internal final class ClientInterceptorPipeline<Request, Response> {
  /// A logger.
  @usableFromInline
  internal var logger: GRPCLogger

  /// The `EventLoop` this RPC is being executed on.
  @usableFromInline
  internal let eventLoop: EventLoop

  /// The details of the call.
  @usableFromInline
  internal let details: CallDetails

  /// A task for closing the RPC in case of a timeout.
  @usableFromInline
  internal var _scheduledClose: Scheduled<Void>?

  @usableFromInline
  internal let _errorDelegate: ClientErrorDelegate?

  @usableFromInline
  internal let _onError: (Error) -> Void

  @usableFromInline
  internal let _onCancel: (EventLoopPromise<Void>?) -> Void

  @usableFromInline
  internal let _onRequestPart: (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void

  @usableFromInline
  internal let _onResponsePart: (GRPCClientResponsePart<Response>) -> Void

  /// The index after the last user interceptor context index. (i.e. `_userContexts.endIndex`).
  @usableFromInline
  internal let _headIndex: Int

  /// The index before the first user interceptor context index (always -1).
  @usableFromInline
  internal let _tailIndex: Int

  @usableFromInline
  internal var _userContexts: [ClientInterceptorContext<Request, Response>]

  /// Whether the interceptor pipeline is still open. It becomes closed after an 'end' response
  /// part has traversed the pipeline.
  @usableFromInline
  internal var _isOpen = true

  /// The index of the next context on the inbound side of the context at the given index.
  @inlinable
  internal func _nextInboundIndex(after index: Int) -> Int {
    // Unchecked arithmetic is okay here: our smallest inbound index is '_tailIndex' but we will
    // never ask for the inbound index after the tail.
    assert(self._indexIsValid(index))
    return index &- 1
  }

  /// The index of the next context on the outbound side of the context at the given index.
  @inlinable
  internal func _nextOutboundIndex(after index: Int) -> Int {
    // Unchecked arithmetic is okay here: our greatest outbound index is '_headIndex' but we will
    // never ask for the outbound index after the head.
    assert(self._indexIsValid(index))
    return index &+ 1
  }

  /// Returns true of the index is in the range `_tailIndex ... _headIndex`.
  @inlinable
  internal func _indexIsValid(_ index: Int) -> Bool {
    return index >= self._tailIndex && index <= self._headIndex
  }

  @inlinable
  internal init(
    eventLoop: EventLoop,
    details: CallDetails,
    logger: GRPCLogger,
    interceptors: [ClientInterceptor<Request, Response>],
    errorDelegate: ClientErrorDelegate?,
    onError: @escaping (Error) -> Void,
    onCancel: @escaping (EventLoopPromise<Void>?) -> Void,
    onRequestPart: @escaping (GRPCClientRequestPart<Request>, EventLoopPromise<Void>?) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop = eventLoop
    self.details = details
    self.logger = logger

    self._errorDelegate = errorDelegate
    self._onError = onError
    self._onCancel = onCancel
    self._onRequestPart = onRequestPart
    self._onResponsePart = onResponsePart

    // The tail is before the interceptors.
    self._tailIndex = -1
    // The head is after the interceptors.
    self._headIndex = interceptors.endIndex

    // Make some contexts.
    self._userContexts = []
    self._userContexts.reserveCapacity(interceptors.count)

    for index in 0 ..< interceptors.count {
      let context = ClientInterceptorContext(for: interceptors[index], atIndex: index, in: self)
      self._userContexts.append(context)
    }

    self._setupDeadline()
  }

  /// Emit a response part message into the interceptor pipeline.
  ///
  /// This should be called by the transport layer when receiving a response part from the server.
  ///
  /// - Parameter part: The part to emit into the pipeline.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func receive(_ part: GRPCClientResponsePart<Response>) {
    self.invokeReceive(part, fromContextAtIndex: self._headIndex)
  }

  /// Invoke receive on the appropriate context when called from the context at the given index.
  @inlinable
  internal func invokeReceive(
    _ part: GRPCClientResponsePart<Response>,
    fromContextAtIndex index: Int
  ) {
    self._invokeReceive(part, onContextAtIndex: self._nextInboundIndex(after: index))
  }

  /// Invoke receive on the context at the given index, if doing so is safe.
  @inlinable
  internal func _invokeReceive(
    _ part: GRPCClientResponsePart<Response>,
    onContextAtIndex index: Int
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      return
    }

    self._invokeReceive(part, onContextAtUncheckedIndex: index)
  }

  /// Invoke receive on the context at the given index, assuming that the index is valid and the
  /// pipeline is still open.
  @inlinable
  internal func _invokeReceive(
    _ part: GRPCClientResponsePart<Response>,
    onContextAtUncheckedIndex index: Int
  ) {
    switch index {
    case self._headIndex:
      self._invokeReceive(part, onContextAtUncheckedIndex: self._nextInboundIndex(after: index))

    case self._tailIndex:
      if part.isEnd {
        self.close()
      }
      self._onResponsePart(part)

    default:
      self._userContexts[index].invokeReceive(part)
    }
  }

  /// Emit an error into the interceptor pipeline.
  ///
  /// This should be called by the transport layer when receiving an error.
  ///
  /// - Parameter error: The error to emit.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func errorCaught(_ error: Error) {
    self.invokeErrorCaught(error, fromContextAtIndex: self._headIndex)
  }

  /// Invoke `errorCaught` on the appropriate context when called from the context at the given
  /// index.
  @inlinable
  internal func invokeErrorCaught(_ error: Error, fromContextAtIndex index: Int) {
    self._invokeErrorCaught(error, onContextAtIndex: self._nextInboundIndex(after: index))
  }

  /// Invoke `errorCaught` on the context at the given index if that index exists and the pipeline
  /// is still open.
  @inlinable
  internal func _invokeErrorCaught(_ error: Error, onContextAtIndex index: Int) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      return
    }
    self._invokeErrorCaught(error, onContextAtUncheckedIndex: index)
  }

  /// Invoke `errorCaught` on the context at the given index assuming the index exists and the
  /// pipeline is still open.
  @inlinable
  internal func _invokeErrorCaught(_ error: Error, onContextAtUncheckedIndex index: Int) {
    switch index {
    case self._headIndex:
      self._invokeErrorCaught(error, onContextAtIndex: self._nextInboundIndex(after: index))

    case self._tailIndex:
      self._errorCaught(error)

    default:
      self._userContexts[index].invokeErrorCaught(error)
    }
  }

  /// Handles a caught error which has traversed the interceptor pipeline.
  @usableFromInline
  internal func _errorCaught(_ error: Error) {
    // We're about to complete, close the pipeline.
    self.close()

    var unwrappedError: Error

    // Unwrap the error, if possible.
    if let errorContext = error as? GRPCError.WithContext {
      unwrappedError = errorContext.error
      self._errorDelegate?.didCatchError(
        errorContext.error,
        logger: self.logger.unwrapped,
        file: errorContext.file,
        line: errorContext.line
      )
    } else {
      unwrappedError = error
      self._errorDelegate?.didCatchErrorWithoutContext(error, logger: self.logger.unwrapped)
    }

    // Emit the unwrapped error.
    self._onError(unwrappedError)
  }

  /// Writes a request message into the interceptor pipeline.
  ///
  /// This should be called by the call object to send requests parts to the transport.
  ///
  /// - Parameters:
  ///   - part: The request part to write.
  ///   - promise: A promise to complete when the request part has been successfully written.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func send(_ part: GRPCClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.invokeSend(part, promise: promise, fromContextAtIndex: self._tailIndex)
  }

  /// Invoke send on the appropriate context when called from the context at the given index.
  @inlinable
  internal func invokeSend(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    fromContextAtIndex index: Int
  ) {
    self._invokeSend(
      part,
      promise: promise,
      onContextAtIndex: self._nextOutboundIndex(after: index)
    )
  }

  /// Invoke send on the context at the given index, if it exists and the pipeline is still open.
  @inlinable
  internal func _invokeSend(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    onContextAtIndex index: Int
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      promise?.fail(GRPCError.AlreadyComplete())
      return
    }
    self._invokeSend(part, promise: promise, onContextAtUncheckedIndex: index)
  }

  /// Invoke send on the context at the given index assuming the index exists and the pipeline is
  /// still open.
  @inlinable
  internal func _invokeSend(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    onContextAtUncheckedIndex index: Int
  ) {
    switch index {
    case self._headIndex:
      self._onRequestPart(part, promise)

    case self._tailIndex:
      self._invokeSend(
        part,
        promise: promise,
        onContextAtUncheckedIndex: self._nextOutboundIndex(after: index)
      )

    default:
      self._userContexts[index].invokeSend(part, promise: promise)
    }
  }

  /// Send a request to cancel the RPC through the interceptor pipeline.
  ///
  /// This should be called by the call object when attempting to cancel the RPC.
  ///
  /// - Parameter promise: A promise to complete when the cancellation request has been handled.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func cancel(promise: EventLoopPromise<Void>?) {
    self.invokeCancel(promise: promise, fromContextAtIndex: self._tailIndex)
  }

  /// Invoke `cancel` on the appropriate context when called from the context at the given index.
  @inlinable
  internal func invokeCancel(promise: EventLoopPromise<Void>?, fromContextAtIndex index: Int) {
    self._invokeCancel(promise: promise, onContextAtIndex: self._nextOutboundIndex(after: index))
  }

  /// Invoke `cancel` on the context at the given index if the index is valid and the pipeline is
  /// still open.
  @inlinable
  internal func _invokeCancel(
    promise: EventLoopPromise<Void>?,
    onContextAtIndex index: Int
  ) {
    self.eventLoop.assertInEventLoop()
    assert(self._indexIsValid(index))
    guard self._isOpen else {
      promise?.fail(GRPCError.AlreadyComplete())
      return
    }
    self._invokeCancel(promise: promise, onContextAtUncheckedIndex: index)
  }

  /// Invoke `cancel` on the context at the given index assuming the index is valid and the
  /// pipeline is still open.
  @inlinable
  internal func _invokeCancel(
    promise: EventLoopPromise<Void>?,
    onContextAtUncheckedIndex index: Int
  ) {
    switch index {
    case self._headIndex:
      self._onCancel(promise)

    case self._tailIndex:
      self._invokeCancel(
        promise: promise,
        onContextAtUncheckedIndex: self._nextOutboundIndex(after: index)
      )

    default:
      self._userContexts[index].invokeCancel(promise: promise)
    }
  }
}

// MARK: - Lifecycle

extension ClientInterceptorPipeline {
  /// Closes the pipeline. This should be called once, by the tail interceptor, to indicate that
  /// the RPC has completed.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func close() {
    self.eventLoop.assertInEventLoop()
    self._isOpen = false

    // Cancel the timeout.
    self._scheduledClose?.cancel()
    self._scheduledClose = nil

    // Cancel the transport.
    self._onCancel(nil)
  }

  /// Sets up a deadline for the pipeline.
  @inlinable
  internal func _setupDeadline() {
    func setup() {
      self.eventLoop.assertInEventLoop()

      let timeLimit = self.details.options.timeLimit
      let deadline = timeLimit.makeDeadline()

      // There's no point scheduling this.
      if deadline == .distantFuture {
        return
      }

      self._scheduledClose = self.eventLoop.scheduleTask(deadline: deadline) {
        // When the error hits the tail we'll call 'close()', this will cancel the transport if
        // necessary.
        self.errorCaught(GRPCError.RPCTimedOut(timeLimit))
      }
    }

    if self.eventLoop.inEventLoop {
      setup()
    } else {
      self.eventLoop.execute {
        setup()
      }
    }
  }
}

extension ClientInterceptorContext {
  @inlinable
  internal func invokeReceive(_ part: GRPCClientResponsePart<Response>) {
    self.interceptor.receive(part, context: self)
  }

  @inlinable
  internal func invokeSend(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.interceptor.send(part, promise: promise, context: self)
  }

  @inlinable
  internal func invokeCancel(promise: EventLoopPromise<Void>?) {
    self.interceptor.cancel(promise: promise, context: self)
  }

  @inlinable
  internal func invokeErrorCaught(_ error: Error) {
    self.interceptor.errorCaught(error, context: self)
  }
}
