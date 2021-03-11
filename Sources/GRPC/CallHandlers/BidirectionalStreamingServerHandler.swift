/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import NIO
import NIOHPACK

public final class BidirectionalStreamingServerHandler<
  Serializer: MessageSerializer,
  Deserializer: MessageDeserializer
>: GRPCServerHandlerProtocol {
  public typealias Request = Deserializer.Output
  public typealias Response = Serializer.Input

  /// A response serializer.
  @usableFromInline
  internal let serializer: Serializer

  /// A request deserializer.
  @usableFromInline
  internal let deserializer: Deserializer

  /// A pipeline of user provided interceptors.
  @usableFromInline
  internal var interceptors: ServerInterceptorPipeline<Request, Response>!

  /// Stream events which have arrived before the stream observer future has been resolved.
  @usableFromInline
  internal var requestBuffer: CircularBuffer<StreamEvent<Request>> = CircularBuffer()

  /// The context required in order create the function.
  @usableFromInline
  internal let context: CallHandlerContext

  /// A reference to a `UserInfo`.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// The user provided function to execute.
  @usableFromInline
  internal let observerFactory: (_StreamingResponseCallContext<Request, Response>)
    -> EventLoopFuture<(StreamEvent<Request>) -> Void>

  /// The state of the handler.
  @usableFromInline
  internal var state: State = .idle

  @usableFromInline
  internal enum State {
    // No headers have been received.
    case idle
    // Headers have been received, a context has been created and the user code has been called to
    // make a stream observer with. The observer is yet to see any messages.
    case creatingObserver(_StreamingResponseCallContext<Request, Response>)
    // The observer future has resolved and the observer may have seen messages.
    case observing((StreamEvent<Request>) -> Void, _StreamingResponseCallContext<Request, Response>)
    // The observer has completed by completing the status promise.
    case completed
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    observerFactory: @escaping (StreamingResponseCallContext<Response>)
      -> EventLoopFuture<(StreamEvent<Request>) -> Void>
  ) {
    self.serializer = responseSerializer
    self.deserializer = requestDeserializer
    self.context = context
    self.observerFactory = observerFactory

    let userInfoRef = Ref(UserInfo())
    self.userInfoRef = userInfoRef
    self.interceptors = ServerInterceptorPipeline(
      logger: context.logger,
      eventLoop: context.eventLoop,
      path: context.path,
      callType: .bidirectionalStreaming,
      remoteAddress: context.remoteAddress,
      userInfoRef: userInfoRef,
      interceptors: interceptors,
      onRequestPart: self.receiveInterceptedPart(_:),
      onResponsePart: self.sendInterceptedPart(_:promise:)
    )
  }

  // MARK: - Public API: gRPC to Handler

  @inlinable
  public func receiveMetadata(_ headers: HPACKHeaders) {
    self.interceptors.receive(.metadata(headers))
  }

  @inlinable
  public func receiveMessage(_ bytes: ByteBuffer) {
    do {
      let message = try self.deserializer.deserialize(byteBuffer: bytes)
      self.interceptors.receive(.message(message))
    } catch {
      self.handleError(error)
    }
  }

  @inlinable
  public func receiveEnd() {
    self.interceptors.receive(.end)
  }

  @inlinable
  public func receiveError(_ error: Error) {
    self.handleError(error)
    self.finish()
  }

  @inlinable
  public func finish() {
    switch self.state {
    case .idle:
      self.interceptors = nil
      self.state = .completed

    case let .creatingObserver(context),
         let .observing(_, context):
      context.statusPromise.fail(GRPCStatus(code: .unavailable, message: nil))

    case .completed:
      self.interceptors = nil
    }
  }

  // MARK: - Interceptors to User Function

  @inlinable
  internal func receiveInterceptedPart(_ part: GRPCServerRequestPart<Request>) {
    switch part {
    case let .metadata(headers):
      self.receiveInterceptedMetadata(headers)
    case let .message(message):
      self.receiveInterceptedMessage(message)
    case .end:
      self.receiveInterceptedEnd()
    }
  }

  @inlinable
  internal func receiveInterceptedMetadata(_ headers: HPACKHeaders) {
    switch self.state {
    case .idle:
      // Make a context to invoke the observer block factory with.
      let context = _StreamingResponseCallContext<Request, Response>(
        eventLoop: self.context.eventLoop,
        headers: headers,
        logger: self.context.logger,
        userInfoRef: self.userInfoRef,
        compressionIsEnabled: self.context.encoding.isEnabled,
        closeFuture: self.context.closeFuture,
        sendResponse: self.interceptResponse(_:metadata:promise:)
      )

      // Move to the next state.
      self.state = .creatingObserver(context)

      // Send response headers back via the interceptors.
      self.interceptors.send(.metadata([:]), promise: nil)

      // Register callbacks on the status future.
      context.statusPromise.futureResult.whenComplete(self.userFunctionStatusResolved(_:))

      // Make an observer block and register a completion block.
      self.observerFactory(context).whenComplete(self.userFunctionResolvedWithResult(_:))

    case .creatingObserver, .observing:
      self.handleError(GRPCError.ProtocolViolation("Multiple header blocks received on RPC"))

    case .completed:
      // We may receive headers from the interceptor pipeline if we have already finished (i.e. due
      // to an error or otherwise) and an interceptor doing some async work later emitting headers.
      // Dropping them is fine.
      ()
    }
  }

  @inlinable
  internal func receiveInterceptedMessage(_ request: Request) {
    switch self.state {
    case .idle:
      self.handleError(GRPCError.ProtocolViolation("Message received before headers"))
    case .creatingObserver:
      self.requestBuffer.append(.message(request))
    case let .observing(observer, _):
      observer(.message(request))
    case .completed:
      // We received a message but we're already done: this may happen if we terminate the RPC
      // due to a channel error, for example.
      ()
    }
  }

  @inlinable
  internal func receiveInterceptedEnd() {
    switch self.state {
    case .idle:
      self.handleError(GRPCError.ProtocolViolation("End of stream received before headers"))
    case .creatingObserver:
      self.requestBuffer.append(.end)
    case let .observing(observer, _):
      observer(.end)
    case .completed:
      // We received a message but we're already done: this may happen if we terminate the RPC
      // due to a channel error, for example.
      ()
    }
  }

  // MARK: - User Function To Interceptors

  @inlinable
  internal func userFunctionResolvedWithResult(
    _ result: Result<(StreamEvent<Request>) -> Void, Error>
  ) {
    switch self.state {
    case .idle, .observing:
      // The observer block can't resolve if it hasn't been created ('idle') and it can't be
      // resolved more than once ('observing').
      preconditionFailure()

    case let .creatingObserver(context):
      switch result {
      case let .success(observer):
        // We have an observer block now; unbuffer any requests.
        self.state = .observing(observer, context)
        while let request = self.requestBuffer.popFirst() {
          observer(request)
        }

      case let .failure(error):
        self.handleError(error, thrownFromHandler: true)
      }

    case .completed:
      // We've already completed. That's fine.
      ()
    }
  }

  @inlinable
  internal func interceptResponse(
    _ response: Response,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.state {
    case .idle:
      // The observer block can't end responses if it doesn't exist!
      preconditionFailure()

    case .creatingObserver, .observing:
      // The user has access to the response context before returning a future observer,
      // so 'creatingObserver' is valid here (if a little strange).
      self.interceptors.send(.message(response, metadata), promise: promise)

    case .completed:
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  @inlinable
  internal func userFunctionStatusResolved(_ result: Result<GRPCStatus, Error>) {
    switch self.state {
    case .idle:
      // The promise can't fail before we create it.
      preconditionFailure()

    // Making is possible, the user can complete the status before returning a stream handler.
    case let .creatingObserver(context), let .observing(_, context):
      switch result {
      case let .success(status):
        // We're sending end back, we're done.
        self.state = .completed
        self.interceptors.send(.end(status, context.trailers), promise: nil)

      case let .failure(error):
        self.handleError(error, thrownFromHandler: true)
      }

    case .completed:
      ()
    }
  }

  @inlinable
  internal func handleError(_ error: Error, thrownFromHandler isHandlerError: Bool = false) {
    switch self.state {
    case .idle:
      assert(!isHandlerError)
      self.state = .completed
      // We don't have a promise to fail. Just send back end.
      let (status, trailers) = ServerErrorProcessor.processLibraryError(
        error,
        delegate: self.context.errorDelegate
      )
      self.interceptors.send(.end(status, trailers), promise: nil)

    case let .creatingObserver(context),
         let .observing(_, context):
      // We don't have a promise to fail. Just send back end.
      self.state = .completed

      let status: GRPCStatus
      let trailers: HPACKHeaders

      if isHandlerError {
        (status, trailers) = ServerErrorProcessor.processObserverError(
          error,
          headers: context.headers,
          trailers: context.trailers,
          delegate: self.context.errorDelegate
        )
      } else {
        (status, trailers) = ServerErrorProcessor.processLibraryError(
          error,
          delegate: self.context.errorDelegate
        )
      }

      self.interceptors.send(.end(status, trailers), promise: nil)
      // We're already in the 'completed' state so failing the promise will be a no-op in the
      // callback to 'userFunctionStatusResolved' (but we also need to avoid leaking the promise.)
      context.statusPromise.fail(error)

    case .completed:
      ()
    }
  }

  @inlinable
  internal func sendInterceptedPart(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    switch part {
    case let .metadata(headers):
      self.context.responseWriter.sendMetadata(headers, flush: true, promise: promise)

    case let .message(message, metadata):
      do {
        let bytes = try self.serializer.serialize(message, allocator: ByteBufferAllocator())
        self.context.responseWriter.sendMessage(bytes, metadata: metadata, promise: promise)
      } catch {
        // Serialization failed: fail the promise and send end.
        promise?.fail(error)
        let (status, trailers) = ServerErrorProcessor.processLibraryError(
          error,
          delegate: self.context.errorDelegate
        )
        // Loop back via the interceptors.
        self.interceptors.send(.end(status, trailers), promise: nil)
      }

    case let .end(status, trailers):
      self.context.responseWriter.sendEnd(status: status, trailers: trailers, promise: promise)
    }
  }
}
