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
    wrapping unary: @escaping @Sendable(Request, GRPCAsyncServerCallContext) async throws
      -> Response
  ) {
    self._handler = .init(
      context: context,
      requestDeserializer: requestDeserializer,
      responseSerializer: responseSerializer,
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
  internal let userHandler: @Sendable(
    GRPCAsyncRequestStream<Request>,
    GRPCAsyncResponseStreamWriter<Response>,
    GRPCAsyncServerCallContext
  ) async throws -> Void

  /// The state of the handler.
  @usableFromInline
  internal var state: State = .idle

  /// The task used to run the async user handler.
  ///
  /// - TODO: I'd like it if this was part of the assoc data for the .active state but doing so may introduce a race condition.
  @usableFromInline
  internal var userHandlerTask: Task<Void, Never>? = nil

  @usableFromInline
  internal enum State {
    /// No headers have been received.
    case idle

    @usableFromInline
    internal struct ActiveState {
      /// The source backing the request stream that is being consumed by the user handler.
      @usableFromInline
      let requestStreamSource: PassthroughMessageSource<Request, Error>

      /// The call context that was passed to the user handler.
      @usableFromInline
      let context: GRPCAsyncServerCallContext

      /// The response stream writer that is being used by the user handler.
      ///
      /// Because this is pausable, it may contain responses after the user handler has completed
      /// that have yet to be written. However we will remain in the `.active` state until the
      /// response stream writer has completed.
      @usableFromInline
      let responseStreamWriter: GRPCAsyncResponseStreamWriter<Response>

      /// The response headers have been sent back to the client via the interceptors.
      @usableFromInline
      var haveSentResponseHeaders: Bool = false

      /// The promise we are using to bridge the NIO and async-await worlds.
      ///
      /// It is the mechanism that we use to run a callback when the user handler has completed.
      /// The promise is not passed to the user handler directly. Instead it is fulfilled with the
      /// result of the async `Task` executing the user handler using `completeWithTask(_:)`.
      ///
      /// - TODO: It shouldn't really be necessary to stash this promise here. Specifically it is
      /// never used anywhere when the `.active` enum value is accessed. However, if we do not store
      /// it here then the tests periodically segfault. This appears to be a reference counting bug
      /// in Swift and/or NIO since it should have been captured by `completeWithTask(_:)`.
      let _userHandlerPromise: EventLoopPromise<Void>

      @usableFromInline
      internal init(
        requestStreamSource: PassthroughMessageSource<Request, Error>,
        context: GRPCAsyncServerCallContext,
        responseStreamWriter: GRPCAsyncResponseStreamWriter<Response>,
        userHandlerPromise: EventLoopPromise<Void>
      ) {
        self.requestStreamSource = requestStreamSource
        self.context = context
        self.responseStreamWriter = responseStreamWriter
        self._userHandlerPromise = userHandlerPromise
      }
    }

    /// Headers have been received and an async `Task` has been created to execute the user handler.
    case active(ActiveState)

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

    case .active:
      self.state = .completed
      self.interceptors = nil
      self.userHandlerTask?.cancel()

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
      // Make a context to invoke the user handler with.
      let context = GRPCAsyncServerCallContext(
        headers: headers,
        logger: self.context.logger,
        userInfoRef: self.userInfoRef
      )

      // Create a source for our request stream.
      let requestStreamSource = PassthroughMessageSource<Request, Error>()

      // Create a promise to hang a callback off when the user handler completes.
      let userHandlerPromise: EventLoopPromise<Void> = self.context.eventLoop.makePromise()

      // Create a request stream from our stream source to pass to the user handler.
      let requestStream = GRPCAsyncRequestStream(.init(consuming: requestStreamSource))

      // TODO: In future use `AsyncWriter.init(maxPendingElements:maxWritesBeforeYield:delegate:)`?
      let responseStreamWriter =
        GRPCAsyncResponseStreamWriter(
          wrapping: AsyncWriter(delegate: AsyncResponseStreamWriterDelegate(
            context: context,
            compressionIsEnabled: self.context.encoding.isEnabled,
            send: self.interceptResponse(_:metadata:),
            finish: self.responseStreamDrained(_:)
          ))
        )

      // Set the state to active and bundle in all the associated data.
      self.state = .active(.init(
        requestStreamSource: requestStreamSource,
        context: context,
        responseStreamWriter: responseStreamWriter,
        userHandlerPromise: userHandlerPromise
      ))

      // Register callback for the completion of the user handler.
      userHandlerPromise.futureResult.whenComplete(self.userHandlerCompleted(_:))

      // Spin up a task to call the async user handler.
      self.userHandlerTask = userHandlerPromise.completeWithTask {
        return try await withTaskCancellationHandler {
          do {
            // When the user handler completes we invalidate the request stream source.
            defer { requestStreamSource.finish() }
            // Call the user handler.
            try await self.userHandler(requestStream, responseStreamWriter, context)
          } catch let status as GRPCStatus where status.isOk {
            // The user handler throwing `GRPCStatus.ok` is considered to be invalid.
            await responseStreamWriter.asyncWriter.cancel()
            throw GRPCStatus(
              code: .unknown,
              message: "Handler threw GRPCStatus error with code .ok"
            )
          } catch {
            await responseStreamWriter.asyncWriter.cancel()
            throw error
          }
          // Wait for the response stream writer to finish writing its responses.
          try await responseStreamWriter.asyncWriter.finish(.ok)
        } onCancel: {
          /// The task being cancelled from outside is the signal to this task that an error has
          /// occured and we should abort the user handler.
          ///
          /// Adopters are encouraged to cooperatively check for cancellation in their handlers but
          /// we cannot rely on this.
          ///
          /// We additionally signal the handler that an error has occured by terminating the source
          /// backing the request stream that the user handler is consuming.
          ///
          /// - NOTE: This handler has different semantics from the extant non-async-await handlers
          /// where the `statusPromise` was explicitly failed with `GRPCStatus.unavailable` from
          /// _outside_ the user handler. Here we terminate the request stream with a
          /// `CancellationError` which manifests _inside_ the user handler when it tries to access
          /// the next request in the stream. We have no control over the implementation of the user
          /// handler. It may choose to handle this error or not. In the event that the handler
          /// either rethrows or does not handle the error, this will be converted to a
          /// `GRPCStatus.unknown` by `handleError(_:)`. Yielding a `CancellationError` _inside_
          /// the user handler feels like the clearest semantics of what we want--"the RPC has an
          /// error, cancel whatever you're doing." If we want to preserve the API of the
          /// non-async-await handlers in this error flow we could add conformance to
          /// `GRPCStatusTransformable` to `CancellationError`, but we still cannot control _how_
          /// the user handler will handle the `CancellationError` which could even be swallowed.
          ///
          /// - NOTE: Currently we _have_ added `GRPCStatusTransformable` conformance to
          /// `CancellationError` to convert it into `GRPCStatus.unavailable` and expect to
          /// document that user handlers should always rethrow `CacellationError` if handled, after
          /// optional cleanup.
          requestStreamSource.finish(throwing: CancellationError())
          /// Cancel the writer here to drop any pending responses.
          responseStreamWriter.asyncWriter.cancelAsynchronously()
        }
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
    case let .active(activeState):
      switch activeState.requestStreamSource.yield(request) {
      case .accepted(queueDepth: _):
        // TODO: In future we will potentially issue a read request to the channel based on the value of `queueDepth`.
        break
      case .dropped:
        /// If we are in the `.active` state then we have yet to encounter an error. Therefore
        /// if the request stream source has already terminated then it must have been the result of
        /// receiving `.end`. Therefore this `.message` must have been sent by the client after it
        /// sent `.end`, which is a protocol violation.
        self.handleError(GRPCError.ProtocolViolation("Message received after end of stream"))
      }
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
    case let .active(activeState):
      switch activeState.requestStreamSource.finish() {
      case .accepted(queueDepth: _):
        break
      case .dropped:
        // The task executing the user handler will finish the request stream source after the
        // user handler completes. If that's the case we will drop the end-of-stream here.
        break
      }
    case .completed:
      // We received a message but we're already done: this may happen if we terminate the RPC
      // due to a channel error, for example.
      ()
    }
  }

  // MARK: - User Function To Interceptors

  @inlinable
  internal func _interceptResponse(_ response: Response, metadata: MessageMetadata) {
    self.context.eventLoop.assertInEventLoop()
    switch self.state {
    case .idle:
      // The user handler cannot send responses before it has been invoked.
      preconditionFailure()

    case var .active(activeState):
      if !activeState.haveSentResponseHeaders {
        activeState.haveSentResponseHeaders = true
        self.state = .active(activeState)
        // Send response headers back via the interceptors.
        self.interceptors.send(.metadata(activeState.context.initialResponseMetadata), promise: nil)
      }
      // Send the response back via the interceptors.
      self.interceptors.send(.message(response, metadata), promise: nil)

    case .completed:
      /// If we are in the completed state then the async writer delegate will have been cancelled,
      /// however the cancellation is asynchronous so there's a chance that we receive this callback
      /// after that has happened. We can drop the response.
      ()
    }
  }

  @Sendable
  @inlinable
  internal func interceptResponse(_ response: Response, metadata: MessageMetadata) {
    if self.context.eventLoop.inEventLoop {
      self._interceptResponse(response, metadata: metadata)
    } else {
      self.context.eventLoop.execute {
        self._interceptResponse(response, metadata: metadata)
      }
    }
  }

  @inlinable
  internal func userHandlerCompleted(_ result: Result<Void, Error>) {
    switch self.state {
    case .idle:
      // The user handler cannot complete before it is invoked.
      preconditionFailure()

    case .active:
      switch result {
      case .success:
        /// The user handler has completed successfully.
        /// We don't take any action here; the state transition and termination of the message
        /// stream happen when the response stream has drained, in the response stream writer
        /// delegate callback, `responseStreamDrained(_:)`.
        break

      case let .failure(error):
        self.handleError(error, thrownFromHandler: true)
      }

    case .completed:
      ()
    }
  }

  @inlinable
  internal func _responseStreamDrained(_ status: GRPCStatus) {
    self.context.eventLoop.assertInEventLoop()
    switch self.state {
    case .idle:
      preconditionFailure()

    case let .active(activeState):
      // Now we have drained the response stream writer from the user handler we can send end.
      self.state = .completed
      self.interceptors.send(
        .end(status, activeState.context.trailingResponseMetadata),
        promise: nil
      )

    case .completed:
      ()
    }
  }

  @Sendable
  @inlinable
  internal func responseStreamDrained(_ status: GRPCStatus) {
    if self.context.eventLoop.inEventLoop {
      self._responseStreamDrained(status)
    } else {
      self.context.eventLoop.execute {
        self._responseStreamDrained(status)
      }
    }
  }

  @inlinable
  internal func handleError(_ error: Error, thrownFromHandler isHandlerError: Bool = false) {
    switch self.state {
    case .idle:
      assert(!isHandlerError)
      self.state = .completed
      let (status, trailers) = ServerErrorProcessor.processLibraryError(
        error,
        delegate: self.context.errorDelegate
      )
      self.interceptors.send(.end(status, trailers), promise: nil)

    case let .active(activeState):
      self.state = .completed

      // If we have an async task, then cancel it, which will terminate the request stream from
      // which it is reading and give the user handler an opportunity to cleanup.
      self.userHandlerTask?.cancel()

      let status: GRPCStatus
      let trailers: HPACKHeaders

      if isHandlerError {
        (status, trailers) = ServerErrorProcessor.processObserverError(
          error,
          headers: activeState.context.requestMetadata,
          trailers: activeState.context.trailingResponseMetadata,
          delegate: self.context.errorDelegate
        )
      } else {
        (status, trailers) = ServerErrorProcessor.processLibraryError(
          error,
          delegate: self.context.errorDelegate
        )
      }

      // TODO: This doesn't go via the user handler task.
      self.interceptors.send(.end(status, trailers), promise: nil)

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

#endif
