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
#if compiler(>=5.5)

import _NIOConcurrency
import NIOCore
import NIOHPACK

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct GRPCAsyncServerHandler<
  Serializer: MessageSerializer,
  Deserializer: MessageDeserializer
>: GRPCServerHandlerProtocol {
  @usableFromInline
  internal let _handler: _GRPCAsyncServerHandler<Serializer, Deserializer>

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

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension GRPCAsyncServerHandler {
  public typealias Request = Deserializer.Output
  public typealias Response = Serializer.Input

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    wrapping unary: @escaping @Sendable(Request, GRPCAsyncServerCallContext) async throws
      -> Response
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      interceptors: interceptors,
      userHandler: { requestStream, responseStreamWriter, context in
        guard let request = try await requestStream.prefix(1).first(where: { _ in true }) else {
          throw GRPCError.ProtocolViolation("Unary RPC requires request")
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
    wrapping clientStreaming: @escaping @Sendable(
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncServerCallContext
    ) async throws -> Response
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
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
    wrapping serverStreaming: @escaping @Sendable(
      Request,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      interceptors: interceptors,
      userHandler: { requestStream, responseStreamWriter, context in
        guard let request = try await requestStream.prefix(1).first(where: { _ in true }) else {
          throw GRPCError.ProtocolViolation("Unary RPC requires request")
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
    wrapping bidirectional: @escaping @Sendable(
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
      interceptors: interceptors,
      userHandler: bidirectional
    )
  }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
@usableFromInline
internal final class _GRPCAsyncServerHandler<
  Serializer: MessageSerializer,
  Deserializer: MessageDeserializer
>: GRPCServerHandlerProtocol {
  @usableFromInline
  internal typealias Request = Deserializer.Output
  @usableFromInline
  internal typealias Response = Serializer.Input

  /// A response serializer.
  @usableFromInline
  internal let serializer: Serializer

  /// A request deserializer.
  @usableFromInline
  internal let deserializer: Deserializer

  /// A pipeline of user provided interceptors.
  @usableFromInline
  internal var interceptors: ServerInterceptorPipeline<Request, Response>!

  /// The context required in order create the function.
  @usableFromInline
  internal let context: CallHandlerContext

  /// A reference to a `UserInfo`.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// The user provided function to execute.
  @usableFromInline
  internal let userHandler: (
    GRPCAsyncRequestStream<Request>,
    GRPCAsyncResponseStreamWriter<Response>,
    GRPCAsyncServerCallContext
  ) async throws -> Void

  /// The state of the handler.
  @usableFromInline
  internal var state: State = .idle

  /// The task used to run the async user function.
  @usableFromInline
  internal var task: Task<Void, Never>? = nil

  @usableFromInline
  internal enum State {
    /// No headers have been received.
    case idle
    /// Headers have been received, a context and request stream has been created, and an async
    /// `Task` has been created to execute the user handler.
    ///
    /// The `StreamEvent` handler pokes requests into the request stream which is being consumed by
    /// the user handler.
    ///
    /// The `GRPCAsyncServerContext` is a reference to the context that was passed to the user
    /// handler.
    ///
    /// The `EventLoopPromise` bridges the NIO and async-await worlds and is fulfilled by the async
    /// `Task` that runs the user handler.
    case active(
      (StreamEvent<Request>) -> Void,
      GRPCAsyncServerCallContext,
      EventLoopPromise<GRPCStatus>
    )
    /// The handler has completed.
    case completed
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    userHandler: @escaping @Sendable(
      GRPCAsyncRequestStream<Request>,
      GRPCAsyncResponseStreamWriter<Response>,
      GRPCAsyncServerCallContext
    ) async throws -> Void
  ) {
    self.serializer = responseSerializer
    self.deserializer = requestDeserializer
    self.context = context
    self.userHandler = userHandler

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

  // MARK: - GRPCServerHandlerProtocol conformance

  @inlinable
  internal func receiveMetadata(_ headers: HPACKHeaders) {
    self.interceptors.receive(.metadata(headers))
  }

  @inlinable
  internal func receiveMessage(_ bytes: ByteBuffer) {
    do {
      let message = try self.deserializer.deserialize(byteBuffer: bytes)
      self.interceptors.receive(.message(message))
    } catch {
      self.handleError(error)
    }
  }

  @inlinable
  internal func receiveEnd() {
    self.interceptors.receive(.end)
  }

  @inlinable
  internal func receiveError(_ error: Error) {
    self.handleError(error)
    self.finish()
  }

  @inlinable
  internal func finish() {
    switch self.state {
    case .idle:
      self.interceptors = nil
      self.state = .completed

    case let .active(_, _, statusPromise):
      statusPromise.fail(GRPCStatus(code: .unavailable, message: nil))

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
      let statusPromise: EventLoopPromise<GRPCStatus> = context.eventLoop.makePromise()

      // Make a context to invoke the user handler with.
      let context = GRPCAsyncServerCallContext(
        headers: headers,
        logger: self.context.logger,
        userInfoRef: self.userInfoRef
      )

      // Create a request stream to pass to the user function and capture the
      // handler in the updated state to allow us to produce more results.
      let requestStream = GRPCAsyncRequestStream<Request>(AsyncThrowingStream { continuation in
        self.state = .active(
          { streamEvent in
            switch streamEvent {
            case let .message(request): continuation.yield(request)
            case .end: continuation.finish()
            }
          },
          context,
          statusPromise
        )
      })

      // Create a writer that the user function can use to pass back responses.
      let responseStreamWriter = GRPCAsyncResponseStreamWriter(
        context: context,
        compressionIsEnabled: self.context.encoding.isEnabled,
        send: self.interceptResponse(_:metadata:)
      )

      // Send response headers back via the interceptors.
      self.interceptors.send(.metadata([:]), promise: nil)

      // Register callbacks on the status future.
      statusPromise.futureResult.whenComplete(self.userFunctionStatusResolved(_:))

      // Spin up a task to call the async user handler.
      self.task = statusPromise.completeWithTask {
        // Check for cancellation before calling the user function.
        // This could be the case if the RPC has been cancelled or had an error before this task
        // has been scheduled.
        guard !Task.isCancelled else {
          throw CancellationError()
        }

        // Call the user function.
        try await self.userHandler(requestStream, responseStreamWriter, context)

        // Check for cancellation after the user function has returned so we don't return OK in the
        // event the RPC was cancelled. This is probably overkill because the `handleError(_:)`
        // will also fail the `statusPromise`.
        guard !Task.isCancelled else {
          throw CancellationError()
        }

        // Returning here completes the `statusPromise` and the `userFunctionStatusResolved(_:)`
        // completion handler will take care of handling errors and moving the state machine along.
        return .ok
      }

    case .active:
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
    case let .active(observer, _, _):
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
    case let .active(observer, _, _):
      observer(.end)
    case .completed:
      // We received a message but we're already done: this may happen if we terminate the RPC
      // due to a channel error, for example.
      ()
    }
  }

  // MARK: - User Function To Interceptors

  @inlinable
  internal func interceptResponse(
    _ response: Response,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    self.context.eventLoop.assertInEventLoop()
    switch self.state {
    case .idle:
      // The observer block can't send responses if it doesn't exist!
      preconditionFailure()

    case .active:
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

    case let .active(_, context, _):
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

    case let .active(_, context, statusPromise):
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
      statusPromise.fail(error)

      // If we have an async task, then cancel it (requires cooperative user function).
      //
      // NOTE: This line used to be before we explicitly fail the status promise but it was exaserbating a race condition and causing crashes. See https://bugs.swift.org/browse/SR-15108.
      if let task = self.task {
        task.cancel()
      }

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

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension _GRPCAsyncServerHandler {
  /// Async-await wrapper for `interceptResponse(_:metadata:promise:)`.
  ///
  /// This will take care of ensuring it executes on the right event loop.
  @inlinable
  internal func interceptResponse(
    _ response: Response,
    metadata: MessageMetadata
  ) async throws {
    let promise = self.context.eventLoop.makePromise(of: Void.self)
    if self.context.eventLoop.inEventLoop {
      self.interceptResponse(response, metadata: metadata, promise: promise)
    } else {
      self.context.eventLoop.execute {
        self.interceptResponse(response, metadata: metadata, promise: promise)
      }
    }
    try await promise.futureResult.get()
  }
}

#endif
