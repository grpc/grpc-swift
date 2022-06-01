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
#if compiler(>=5.6)
import Logging
import NIOCore
import NIOHPACK

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct GRPCAsyncServerHandler<
  Serializer: MessageSerializer,
  Deserializer: MessageDeserializer,
  Request: Sendable,
  Response: Sendable
>: GRPCServerHandlerProtocol where Serializer.Input == Response, Deserializer.Output == Request {
  @usableFromInline
  internal let _handler: AsyncServerHandler<Serializer, Deserializer, Request, Response>

  public func receiveMetadata(_ metadata: HPACKHeaders) {
    self._handler.receiveMetadata(metadata)
  }

  public func receiveMessage(_ bytes: ByteBuffer) {
    self._handler.receiveMessage(bytes)
  }

  public func receiveEnd() {
    self._handler.receiveEnd()
  }

  public func receiveError(_ error: Error) {
    self._handler.receiveError(error)
  }

  public func finish() {
    self._handler.finish()
  }
}

// MARK: - RPC Adapters

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension GRPCAsyncServerHandler {
  public typealias Request = Deserializer.Output
  public typealias Response = Serializer.Input

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    wrapping unary: @escaping @Sendable (Request, GRPCAsyncServerCallContext) async throws
      -> Response
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      callType: .unary,
      interceptors: interceptors,
      userHandler: { requestStream, responseStreamWriter, context in
        var iterator = requestStream.makeAsyncIterator()
        guard let request = try await iterator.next(), try await iterator.next() == nil else {
          throw GRPCError.ProtocolViolation("Unary RPC expects exactly one request")
        }
        let response = try await unary(request, context)
        try await responseStreamWriter.send(response)
      }
    )
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    wrapping clientStreaming: @escaping @Sendable (
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncServerCallContext
    ) async throws -> Response
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      callType: .clientStreaming,
      interceptors: interceptors,
      userHandler: { requestStream, responseStreamWriter, context in
        let response = try await clientStreaming(requestStream, context)
        try await responseStreamWriter.send(response)
      }
    )
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    wrapping serverStreaming: @escaping @Sendable (
      Request,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      callType: .serverStreaming,
      interceptors: interceptors,
      userHandler: { requestStream, responseStreamWriter, context in
        var iterator = requestStream.makeAsyncIterator()
        guard let request = try await iterator.next(), try await iterator.next() == nil else {
          throw GRPCError.ProtocolViolation("Server-streaming RPC expects exactly one request")
        }
        try await serverStreaming(request, responseStreamWriter, context)
      }
    )
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    wrapping bidirectional: @escaping @Sendable (
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      callType: .bidirectionalStreaming,
      interceptors: interceptors,
      userHandler: bidirectional
    )
  }
}

// MARK: - Server Handler

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal final class AsyncServerHandler<
  Serializer: MessageSerializer,
  Deserializer: MessageDeserializer,
  Request: Sendable,
  Response: Sendable
>: GRPCServerHandlerProtocol where Serializer.Input == Response, Deserializer.Output == Request {
  /// A response serializer.
  @usableFromInline
  internal let serializer: Serializer

  /// A request deserializer.
  @usableFromInline
  internal let deserializer: Deserializer

  /// The event loop that this handler executes on.
  @usableFromInline
  internal let eventLoop: EventLoop

  /// A `ByteBuffer` allocator provided by the underlying `Channel`.
  @usableFromInline
  internal let allocator: ByteBufferAllocator

  /// A user-provided error delegate which, if provided, is used to transform errors and potentially
  /// pack errors into trailers.
  @usableFromInline
  internal let errorDelegate: ServerErrorDelegate?

  /// A logger.
  @usableFromInline
  internal let logger: Logger

  /// A reference to the user info. This is shared with the interceptor pipeline and may be accessed
  /// from the async call context. `UserInfo` is _not_ `Sendable` and must always be accessed from
  /// an appropriate event loop.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// Whether compression is enabled on the server and an algorithm has been negotiated with
  /// the client
  @usableFromInline
  internal let compressionEnabledOnRPC: Bool

  /// Whether the RPC method would like to compress responses (if possible). Defaults to true.
  @usableFromInline
  internal var compressResponsesIfPossible: Bool

  /// A state machine for the interceptor pipeline.
  @usableFromInline
  internal private(set) var interceptorStateMachine: ServerInterceptorStateMachine
  /// The interceptor pipeline.
  @usableFromInline
  internal private(set) var interceptors: Optional<ServerInterceptorPipeline<Request, Response>>
  /// An object for writing intercepted responses to the channel.
  @usableFromInline
  internal private(set) var responseWriter: Optional<GRPCServerResponseWriter>

  /// A state machine for the user implemented function.
  @usableFromInline
  internal private(set) var handlerStateMachine: ServerHandlerStateMachine
  /// A bag of components used by the user handler.
  @usableFromInline
  internal private(set) var handlerComponents: Optional<ServerHandlerComponents<
    Request,
    AsyncResponseStreamWriterDelegate<Response>
  >>

  /// The user provided function to execute.
  @usableFromInline
  internal let userHandler: @Sendable (
    GRPCAsyncRequestStream<Request>,
    GRPCAsyncResponseStreamWriter<Response>,
    GRPCAsyncServerCallContext
  ) async throws -> Void

  @inlinable
  internal init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    callType: GRPCCallType,
    interceptors: [ServerInterceptor<Request, Response>],
    userHandler: @escaping @Sendable (
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self.serializer = responseSerializer
    self.deserializer = requestDeserializer
    self.eventLoop = context.eventLoop
    self.allocator = context.allocator
    self.responseWriter = context.responseWriter
    self.errorDelegate = context.errorDelegate
    self.compressionEnabledOnRPC = context.encoding.isEnabled
    self.compressResponsesIfPossible = true
    self.logger = context.logger

    self.userInfoRef = Ref(UserInfo())
    self.handlerStateMachine = .init()
    self.handlerComponents = nil

    self.userHandler = userHandler

    self.interceptorStateMachine = .init()
    self.interceptors = nil
    self.interceptors = ServerInterceptorPipeline(
      logger: context.logger,
      eventLoop: context.eventLoop,
      path: context.path,
      callType: callType,
      remoteAddress: context.remoteAddress,
      userInfoRef: self.userInfoRef,
      interceptors: interceptors,
      onRequestPart: self.receiveInterceptedPart(_:),
      onResponsePart: self.sendInterceptedPart(_:promise:)
    )
  }

  // MARK: - GRPCServerHandlerProtocol conformance

  @inlinable
  internal func receiveMetadata(_ headers: HPACKHeaders) {
    switch self.interceptorStateMachine.interceptRequestMetadata() {
    case .intercept:
      self.interceptors?.receive(.metadata(headers))
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  @inlinable
  internal func receiveMessage(_ bytes: ByteBuffer) {
    let request: Request

    do {
      request = try self.deserializer.deserialize(byteBuffer: bytes)
    } catch {
      return self.cancel(error: error)
    }

    switch self.interceptorStateMachine.interceptRequestMessage() {
    case .intercept:
      self.interceptors?.receive(.message(request))
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  @inlinable
  internal func receiveEnd() {
    switch self.interceptorStateMachine.interceptRequestEnd() {
    case .intercept:
      self.interceptors?.receive(.end)
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  @inlinable
  internal func receiveError(_ error: Error) {
    self.cancel(error: error)
  }

  @inlinable
  internal func finish() {
    self.cancel(error: nil)
  }

  @usableFromInline
  internal func cancel(error: Error?) {
    self.eventLoop.assertInEventLoop()

    switch self.handlerStateMachine.cancel() {
    case .cancelAndNilOutHandlerComponents:
      // Cancel handler related things (task, response writer).
      self.handlerComponents?.cancel()
      self.handlerComponents = nil

      // We don't distinguish between having sent the status or not; we just tell the interceptor
      // state machine that we want to send a response status. It will inform us whether to
      // generate and send one or not.
      switch self.interceptorStateMachine.interceptedResponseStatus() {
      case .forward:
        let error = error ?? GRPCStatus.processingError
        let (status, trailers) = ServerErrorProcessor.processLibraryError(
          error,
          delegate: self.errorDelegate
        )
        self.responseWriter?.sendEnd(status: status, trailers: trailers, promise: nil)
      case .drop, .cancel:
        ()
      }

    case .none:
      ()
    }

    switch self.interceptorStateMachine.cancel() {
    case .sendStatusThenNilOutInterceptorPipeline:
      self.responseWriter?.sendEnd(status: .processingError, trailers: [:], promise: nil)
      fallthrough
    case .nilOutInterceptorPipeline:
      self.interceptors = nil
      self.responseWriter = nil
    case .none:
      ()
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
    switch self.interceptorStateMachine.interceptedRequestMetadata() {
    case .forward:
      () // continue
    case .cancel:
      return self.cancel(error: nil)
    case .drop:
      return
    }

    switch self.handlerStateMachine.handleMetadata() {
    case .invokeHandler:
      // We're going to invoke the handler. We need to create a handful of things in order to do
      // that:
      //
      // - A context which allows the handler to set response headers/trailers and provides them
      //   with a logger amongst other things.
      // - A request source; we push request messages into this which the handler consumes via
      //   an async sequence.
      // - An async writer and delegate. The delegate calls us back with responses. The writer is
      //   passed to the handler.
      //
      // All of these components are held in a bundle ("handler components") outside of the state
      // machine. We release these when we eventually call cancel (either when we `self.cancel()`
      // as a result of an error or when `self.finish()` is called).
      let handlerContext = GRPCAsyncServerCallContext(
        headers: headers,
        logger: self.logger,
        contextProvider: self
      )

      let requestSource = PassthroughMessageSource<Request, Error>()

      let writerDelegate = AsyncResponseStreamWriterDelegate(
        send: self.interceptResponseMessage(_:compression:),
        finish: self.interceptResponseStatus(_:)
      )
      let writer = AsyncWriter(delegate: writerDelegate)

      // The user handler has two exit modes:
      // 1. It completes successfully (the async user function completes without throwing), or
      // 2. It throws an error.
      //
      // On the happy path the 'ok' status is queued up on the async writer. On the error path
      // the writer queue is drained and promise below is completed. When the promise is failed
      // it processes the error (possibly via a delegate) and sends back an appropriate status.
      // We require separate paths as the failure path needs to execute on the event loop to process
      // the error.
      let promise = self.eventLoop.makePromise(of: Void.self)
      // The success path is taken care of by the Task.
      promise.futureResult.whenFailure { error in
        self.userHandlerThrewError(error)
      }

      // Update our state before invoke the handler.
      self.handlerStateMachine.handlerInvoked(requestHeaders: headers)
      self.handlerComponents = ServerHandlerComponents(
        requestSource: requestSource,
        responseWriter: writer,
        task: promise.completeWithTask {
          // We don't have a task cancellation handler here: we do it in `self.cancel()`.
          try await self.invokeUserHandler(
            requestStreamSource: requestSource,
            responseStreamWriter: writer,
            callContext: handlerContext
          )
        }
      )

    case .cancel:
      self.cancel(error: nil)
    }
  }

  @Sendable
  @usableFromInline
  internal func invokeUserHandler(
    requestStreamSource: PassthroughMessageSource<Request, Error>,
    responseStreamWriter: AsyncWriter<AsyncResponseStreamWriterDelegate<Response>>,
    callContext: GRPCAsyncServerCallContext
  ) async throws {
    defer {
      // It's possible the user handler completed before the end of the request stream. We
      // explicitly finish it to drop any unconsumed inbound messages.
      requestStreamSource.finish()
    }

    do {
      let requestStream = GRPCAsyncRequestStream(.init(consuming: requestStreamSource))
      let responseStream = GRPCAsyncResponseStreamWriter(wrapping: responseStreamWriter)
      try await self.userHandler(requestStream, responseStream, callContext)

      // Done successfully. Queue up and send back an 'ok' status.
      try await responseStreamWriter.finish(.ok)
    } catch {
      // Drop pending writes as we're on the error path.
      await responseStreamWriter.cancel()

      if let thrownStatus = error as? GRPCStatus, thrownStatus.isOk {
        throw GRPCStatus(code: .unknown, message: "Handler threw error with status code 'ok'.")
      } else {
        throw error
      }
    }
  }

  @usableFromInline
  internal func userHandlerThrewError(_ error: Error) {
    self.eventLoop.assertInEventLoop()

    switch self.handlerStateMachine.sendStatus() {
    case let .intercept(requestHeaders, trailers):
      let (status, processedTrailers) = ServerErrorProcessor.processObserverError(
        error,
        headers: requestHeaders,
        trailers: trailers,
        delegate: self.errorDelegate
      )

      switch self.interceptorStateMachine.interceptResponseStatus() {
      case .intercept:
        self.interceptors?.send(.end(status, processedTrailers), promise: nil)
      case .cancel:
        self.cancel(error: nil)
      case .drop:
        ()
      }

    case .drop:
      ()
    }
  }

  @inlinable
  internal func receiveInterceptedMessage(_ request: Request) {
    switch self.interceptorStateMachine.interceptedRequestMessage() {
    case .forward:
      switch self.handlerStateMachine.handleMessage() {
      case .forward:
        self.handlerComponents?.requestSource.yield(request)
      case .cancel:
        self.cancel(error: nil)
      }

    case .cancel:
      self.cancel(error: nil)

    case .drop:
      ()
    }
  }

  @inlinable
  internal func receiveInterceptedEnd() {
    switch self.interceptorStateMachine.interceptedRequestEnd() {
    case .forward:
      switch self.handlerStateMachine.handleEnd() {
      case .forward:
        self.handlerComponents?.requestSource.finish()
      case .cancel:
        self.cancel(error: nil)
      }
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  // MARK: - User Function To Interceptors

  @inlinable
  internal func _interceptResponseMessage(_ response: Response, compression: Compression) {
    self.eventLoop.assertInEventLoop()

    switch self.handlerStateMachine.sendMessage() {
    case let .intercept(.some(headers)):
      switch self.interceptorStateMachine.interceptResponseMetadata() {
      case .intercept:
        self.interceptors?.send(.metadata(headers), promise: nil)
      case .cancel:
        return self.cancel(error: nil)
      case .drop:
        ()
      }
      // Fall through to the next case to send the response message.
      fallthrough

    case .intercept(.none):
      switch self.interceptorStateMachine.interceptResponseMessage() {
      case .intercept:
        let senderWantsCompression = compression.isEnabled(
          callDefault: self.compressResponsesIfPossible
        )

        let compress = self.compressionEnabledOnRPC && senderWantsCompression

        let metadata = MessageMetadata(compress: compress, flush: true)
        self.interceptors?.send(.message(response, metadata), promise: nil)
      case .cancel:
        return self.cancel(error: nil)
      case .drop:
        ()
      }

    case .drop:
      ()
    }
  }

  @Sendable
  @inlinable
  internal func interceptResponseMessage(_ response: Response, compression: Compression) {
    if self.eventLoop.inEventLoop {
      self._interceptResponseMessage(response, compression: compression)
    } else {
      self.eventLoop.execute {
        self._interceptResponseMessage(response, compression: compression)
      }
    }
  }

  @inlinable
  internal func _interceptResponseStatus(_ status: GRPCStatus) {
    self.eventLoop.assertInEventLoop()

    switch self.handlerStateMachine.sendStatus() {
    case let .intercept(_, trailers):
      switch self.interceptorStateMachine.interceptResponseStatus() {
      case .intercept:
        self.interceptors?.send(.end(status, trailers), promise: nil)
      case .cancel:
        return self.cancel(error: nil)
      case .drop:
        ()
      }

    case .drop:
      ()
    }
  }

  @Sendable
  @inlinable
  internal func interceptResponseStatus(_ status: GRPCStatus) {
    if self.eventLoop.inEventLoop {
      self._interceptResponseStatus(status)
    } else {
      self.eventLoop.execute {
        self._interceptResponseStatus(status)
      }
    }
  }

  @inlinable
  internal func sendInterceptedPart(
    _ part: GRPCServerResponsePart<Response>,
    promise: EventLoopPromise<Void>?
  ) {
    switch part {
    case let .metadata(headers):
      self.sendInterceptedMetadata(headers, promise: promise)

    case let .message(message, metadata):
      do {
        let bytes = try self.serializer.serialize(message, allocator: ByteBufferAllocator())
        self.sendInterceptedResponse(bytes, metadata: metadata, promise: promise)
      } catch {
        promise?.fail(error)
        self.cancel(error: error)
      }

    case let .end(status, trailers):
      self.sendInterceptedStatus(status, metadata: trailers, promise: promise)
    }
  }

  @inlinable
  internal func sendInterceptedMetadata(
    _ metadata: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.interceptorStateMachine.interceptedResponseMetadata() {
    case .forward:
      if let responseWriter = self.responseWriter {
        responseWriter.sendMetadata(metadata, flush: false, promise: promise)
      } else if let promise = promise {
        promise.fail(GRPCStatus.processingError)
      }
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  @inlinable
  internal func sendInterceptedResponse(
    _ bytes: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.interceptorStateMachine.interceptedResponseMessage() {
    case .forward:
      if let responseWriter = self.responseWriter {
        responseWriter.sendMessage(bytes, metadata: metadata, promise: promise)
      } else if let promise = promise {
        promise.fail(GRPCStatus.processingError)
      }
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }

  @inlinable
  internal func sendInterceptedStatus(
    _ status: GRPCStatus,
    metadata: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.interceptorStateMachine.interceptedResponseStatus() {
    case .forward:
      if let responseWriter = self.responseWriter {
        responseWriter.sendEnd(status: status, trailers: metadata, promise: promise)
      } else if let promise = promise {
        promise.fail(GRPCStatus.processingError)
      }
    case .cancel:
      self.cancel(error: nil)
    case .drop:
      ()
    }
  }
}

// Sendability is unchecked as all mutable state is accessed/modified from an appropriate event
// loop.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncServerHandler: @unchecked Sendable {}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncServerHandler: AsyncServerCallContextProvider {
  @usableFromInline
  internal func setResponseHeaders(_ headers: HPACKHeaders) async throws {
    let completed = self.eventLoop.submit {
      self.handlerStateMachine.setResponseHeaders(headers)
    }
    try await completed.get()
  }

  @usableFromInline
  internal func setResponseTrailers(_ headers: HPACKHeaders) async throws {
    let completed = self.eventLoop.submit {
      self.handlerStateMachine.setResponseTrailers(headers)
    }
    try await completed.get()
  }

  @usableFromInline
  internal func setResponseCompression(_ enabled: Bool) async throws {
    let completed = self.eventLoop.submit {
      self.compressResponsesIfPossible = enabled
    }
    try await completed.get()
  }

  @usableFromInline
  func withUserInfo<Result: Sendable>(
    _ modify: @Sendable @escaping (UserInfo) throws -> Result
  ) async throws -> Result {
    let result = self.eventLoop.submit {
      try modify(self.userInfoRef.value)
    }
    return try await result.get()
  }

  @usableFromInline
  func withMutableUserInfo<Result: Sendable>(
    _ modify: @Sendable @escaping (inout UserInfo) throws -> Result
  ) async throws -> Result {
    let result = self.eventLoop.submit {
      try modify(&self.userInfoRef.value)
    }
    return try await result.get()
  }
}

/// This protocol exists so that the generic server handler can be erased from the
/// `GRPCAsyncServerCallContext`.
///
/// It provides methods which update context on the async handler by first executing onto the
/// correct event loop.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
protocol AsyncServerCallContextProvider: Sendable {
  func setResponseHeaders(_ headers: HPACKHeaders) async throws
  func setResponseTrailers(_ trailers: HPACKHeaders) async throws
  func setResponseCompression(_ enabled: Bool) async throws

  func withUserInfo<Result: Sendable>(
    _ modify: @Sendable @escaping (UserInfo) throws -> Result
  ) async throws -> Result

  func withMutableUserInfo<Result: Sendable>(
    _ modify: @Sendable @escaping (inout UserInfo) throws -> Result
  ) async throws -> Result
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@usableFromInline
internal struct ServerHandlerComponents<Request: Sendable, Delegate: AsyncWriterDelegate> {
  @usableFromInline
  internal let task: Task<Void, Never>
  @usableFromInline
  internal let responseWriter: AsyncWriter<Delegate>
  @usableFromInline
  internal let requestSource: PassthroughMessageSource<Request, Error>

  @inlinable
  init(
    requestSource: PassthroughMessageSource<Request, Error>,
    responseWriter: AsyncWriter<Delegate>,
    task: Task<Void, Never>
  ) {
    self.task = task
    self.responseWriter = responseWriter
    self.requestSource = requestSource
  }

  func cancel() {
    // Cancel the request and response streams.
    //
    // The user handler is encouraged to check for cancellation, however, we should assume
    // they do not. Cancelling the request source stops any more requests from being delivered
    // to the request stream, and cancelling the writer will ensure no more responses are
    // written. This should reduce how long the user handler runs for as it can no longer do
    // anything useful.
    self.requestSource.finish(throwing: CancellationError())
    self.responseWriter.cancelAsynchronously()
    self.task.cancel()
  }
}

#endif // compiler(>=5.6)
