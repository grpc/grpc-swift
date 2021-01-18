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

public final class ServerStreamingServerHandler<
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

  /// The context required in order create the function.
  @usableFromInline
  internal let context: CallHandlerContext

  /// A reference to a `UserInfo`.
  @usableFromInline
  internal let userInfoRef: Ref<UserInfo>

  /// The user provided function to execute.
  @usableFromInline
  internal let userFunction: (Request, StreamingResponseCallContext<Response>)
    -> EventLoopFuture<GRPCStatus>

  /// The state of the handler.
  @usableFromInline
  internal var state: State = .idle

  @usableFromInline
  internal enum State {
    // Initial state. Nothing has happened yet.
    case idle
    // Headers have been received and now we're holding a context with which to invoke the user
    // function when we receive a message.
    case createdContext(_StreamingResponseCallContext<Request, Response>)
    // The user function has been invoked, we're waiting for the status promise to be completed.
    case invokedFunction(_StreamingResponseCallContext<Request, Response>)
    // The function has completed or we are no longer proceeding with execution (because of an error
    // or unexpected closure).
    case completed
  }

  @inlinable
  public init(
    context: CallHandlerContext,
    requestDeserializer: Deserializer,
    responseSerializer: Serializer,
    interceptors: [ServerInterceptor<Request, Response>],
    userFunction: @escaping (Request, StreamingResponseCallContext<Response>)
      -> EventLoopFuture<GRPCStatus>
  ) {
    self.serializer = responseSerializer
    self.deserializer = requestDeserializer
    self.context = context
    self.userFunction = userFunction

    let userInfoRef = Ref(UserInfo())
    self.userInfoRef = userInfoRef
    self.interceptors = ServerInterceptorPipeline(
      logger: context.logger,
      eventLoop: context.eventLoop,
      path: context.path,
      callType: .serverStreaming,
      remoteAddress: context.remoteAddress,
      userInfoRef: userInfoRef,
      interceptors: interceptors,
      onRequestPart: self.receiveInterceptedPart(_:),
      onResponsePart: self.sendInterceptedPart(_:promise:)
    )
  }

  // MARK: Public API; gRPC to Handler

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

    case let .createdContext(context),
         let .invokedFunction(context):
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
        sendResponse: self.interceptResponse(_:metadata:promise:)
      )

      // Move to the next state.
      self.state = .createdContext(context)

      // Register a callback on the status future.
      context.statusPromise.futureResult.whenComplete(self.userFunctionCompletedWithResult(_:))

      // Send response headers back via the interceptors.
      self.interceptors.send(.metadata([:]), promise: nil)

    case .createdContext, .invokedFunction:
      self.handleError(GRPCError.InvalidState("Protocol violation: already received headers"))

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

    case let .createdContext(context):
      self.state = .invokedFunction(context)
      // Complete the status promise with the function outcome.
      context.statusPromise.completeWith(self.userFunction(request, context))

    case .invokedFunction:
      let error = GRPCError.ProtocolViolation("Multiple messages received on server streaming RPC")
      self.handleError(error)

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
      self.handleError(GRPCError.ProtocolViolation("End received before headers"))

    case .createdContext:
      self.handleError(GRPCError.ProtocolViolation("End received before message"))

    case .invokedFunction, .completed:
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
    switch self.state {
    case .idle:
      // The observer block can't send responses if it doesn't exist.
      preconditionFailure()

    case .createdContext, .invokedFunction:
      // The user has access to the response context before returning a future observer,
      // so 'createdContext' is valid here (if a little strange).
      self.interceptors.send(.message(response, metadata), promise: promise)

    case .completed:
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  @inlinable
  internal func userFunctionCompletedWithResult(_ result: Result<GRPCStatus, Error>) {
    switch self.state {
    case .idle:
      // Invalid state: the user function can only completed if it was created.
      preconditionFailure()

    case let .createdContext(context),
         let .invokedFunction(context):

      switch result {
      case let .success(status):
        // We're sending end back, we're done.
        self.state = .completed
        self.interceptors.send(.end(status, context.trailers), promise: nil)

      case let .failure(error):
        self.handleError(error, thrownFromHandler: true)
      }

    case .completed:
      // We've already completed. Ignore this.
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
      self.context.responseWriter.sendMetadata(headers, promise: promise)

    case let .message(message, metadata):
      do {
        let bytes = try self.serializer.serialize(message, allocator: self.context.allocator)
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

    case let .createdContext(context),
         let .invokedFunction(context):
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
      // callback to 'userFunctionCompletedWithResult' (but we also need to avoid leaking the
      // promise.)
      context.statusPromise.fail(error)

    case .completed:
      ()
    }
  }
}
