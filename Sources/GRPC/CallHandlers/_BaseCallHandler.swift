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

/// Provides a means for decoding incoming gRPC messages into protobuf objects.
///
/// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
/// - Important: This is **NOT** part of the public API.
public class _BaseCallHandler<
  RequestDeserializer: MessageDeserializer,
  ResponseSerializer: MessageSerializer
>: GRPCCallHandler, ChannelInboundHandler {
  public typealias RequestPayload = RequestDeserializer.Output
  public typealias ResponsePayload = ResponseSerializer.Input

  public typealias InboundIn = GRPCServerRequestPart<ByteBuffer>
  public typealias OutboundOut = GRPCServerResponsePart<ByteBuffer>

  /// An interceptor pipeline.
  private var pipeline: ServerInterceptorPipeline<RequestPayload, ResponsePayload>?

  /// Our current state.
  private var state: State = .idle

  /// The type of this RPC, e.g. 'unary'.
  private let callType: GRPCCallType

  /// Some context provided to us from the routing handler.
  private let callHandlerContext: CallHandlerContext

  /// A request deserializer.
  private let requestDeserializer: RequestDeserializer

  /// A response serializer.
  private let responseSerializer: ResponseSerializer

  /// The event loop this call is being handled on.
  internal var eventLoop: EventLoop {
    return self.callHandlerContext.eventLoop
  }

  /// An error delegate.
  internal var errorDelegate: ServerErrorDelegate? {
    return self.callHandlerContext.errorDelegate
  }

  /// A logger.
  internal var logger: Logger {
    return self.callHandlerContext.logger
  }

  /// A reference to `UserInfo`.
  internal var userInfoRef: Ref<UserInfo>

  internal init(
    callHandlerContext: CallHandlerContext,
    requestDeserializr: RequestDeserializer,
    responseSerializer: ResponseSerializer,
    callType: GRPCCallType,
    interceptors: [ServerInterceptor<RequestPayload, ResponsePayload>]
  ) {
    let userInfoRef = Ref(UserInfo())
    self.requestDeserializer = requestDeserializr
    self.responseSerializer = responseSerializer
    self.callHandlerContext = callHandlerContext
    self.callType = callType
    self.userInfoRef = userInfoRef
    self.pipeline = ServerInterceptorPipeline(
      logger: callHandlerContext.logger,
      eventLoop: callHandlerContext.eventLoop,
      path: callHandlerContext.path,
      callType: callType,
      userInfoRef: userInfoRef,
      interceptors: interceptors,
      onRequestPart: self.receiveRequestPartFromInterceptors(_:),
      onResponsePart: self.sendResponsePartFromInterceptors(_:promise:)
    )
  }

  // MARK: - ChannelHandler

  public func handlerAdded(context: ChannelHandlerContext) {
    self.act(on: self.state.handlerAdded(context: context))
  }

  public func handlerRemoved(context: ChannelHandlerContext) {
    self.pipeline = nil
  }

  public func channelInactive(context: ChannelHandlerContext) {
    self.pipeline = nil
    context.fireChannelInactive()
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.act(on: self.state.errorCaught(error))
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = self.unwrapInboundIn(data)

    switch part {
    case let .metadata(headers):
      self.act(on: self.state.channelRead(.metadata(headers)))
    case let .message(buffer):
      do {
        let request = try self.requestDeserializer.deserialize(byteBuffer: buffer)
        self.act(on: self.state.channelRead(.message(request)))
      } catch {
        self.errorCaught(context: context, error: error)
      }
    case .end:
      self.act(on: self.state.channelRead(.end))
    }
    // We're the last handler. We don't have anything to forward.
  }

  // MARK: - Event Observer

  internal func observeHeaders(_ headers: HPACKHeaders) {
    fatalError("must be overridden by subclasses")
  }

  internal func observeRequest(_ message: RequestPayload) {
    fatalError("must be overridden by subclasses")
  }

  internal func observeEnd() {
    fatalError("must be overridden by subclasses")
  }

  internal func observeLibraryError(_ error: Error) {
    fatalError("must be overridden by subclasses")
  }

  /// Send a response part to the interceptor pipeline. Called by an event observer.
  /// - Parameters:
  ///   - part: The response part to send.
  ///   - promise: A promise to complete once the response part has been written.
  internal func sendResponsePartFromObserver(
    _ part: GRPCServerResponsePart<ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) {
    self.act(on: self.state.sendResponsePartFromObserver(part, promise: promise))
  }

  /// Processes a library error to form a `GRPCStatus` and trailers to send back to the client.
  /// - Parameter error: The error to process.
  /// - Returns: The status and trailers to send to the client.
  internal func processLibraryError(_ error: Error) -> (GRPCStatus, HPACKHeaders) {
    // Observe the error if we have a delegate.
    self.errorDelegate?.observeLibraryError(error)

    // What status are we terminating this RPC with?
    // - If we have a delegate, try transforming the error. If the delegate returns trailers, merge
    //   them with any on the call context.
    // - If we don't have a delegate, then try to transform the error to a status.
    // - Fallback to a generic error.
    let status: GRPCStatus
    let trailers: HPACKHeaders

    if let transformed = self.errorDelegate?.transformLibraryError(error) {
      status = transformed.status
      trailers = transformed.trailers ?? [:]
    } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
      status = grpcStatusTransformable.makeGRPCStatus()
      trailers = [:]
    } else {
      // Eh... well, we don't what status to use. Use a generic one.
      status = .processingError
      trailers = [:]
    }

    return (status, trailers)
  }

  /// Processes an error, transforming it into a 'GRPCStatus' and any trailers to send to the peer.
  internal func processObserverError(
    _ error: Error,
    headers: HPACKHeaders,
    trailers: HPACKHeaders
  ) -> (GRPCStatus, HPACKHeaders) {
    // Observe the error if we have a delegate.
    self.errorDelegate?.observeRequestHandlerError(error, headers: headers)

    // What status are we terminating this RPC with?
    // - If we have a delegate, try transforming the error. If the delegate returns trailers, merge
    //   them with any on the call context.
    // - If we don't have a delegate, then try to transform the error to a status.
    // - Fallback to a generic error.
    let status: GRPCStatus
    let mergedTrailers: HPACKHeaders

    if let transformed = self.errorDelegate?.transformRequestHandlerError(error, headers: headers) {
      status = transformed.status
      if var transformedTrailers = transformed.trailers {
        // The delegate returned trailers: merge in those from the context as well.
        transformedTrailers.add(contentsOf: trailers)
        mergedTrailers = transformedTrailers
      } else {
        mergedTrailers = trailers
      }
    } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
      status = grpcStatusTransformable.makeGRPCStatus()
      mergedTrailers = trailers
    } else {
      // Eh... well, we don't what status to use. Use a generic one.
      status = .processingError
      mergedTrailers = trailers
    }

    return (status, mergedTrailers)
  }
}

// MARK: - Interceptor API

extension _BaseCallHandler {
  /// Receive a request part from the interceptors pipeline to forward to the event observer.
  /// - Parameter part: The request part to forward.
  private func receiveRequestPartFromInterceptors(_ part: GRPCServerRequestPart<RequestPayload>) {
    self.act(on: self.state.receiveRequestPartFromInterceptors(part))
  }

  /// Send a response part via the `Channel`. Called once the response part has traversed the
  /// interceptor pipeline.
  /// - Parameters:
  ///   - part: The response part to send.
  ///   - promise: A promise to complete once the response part has been written.
  private func sendResponsePartFromInterceptors(
    _ part: GRPCServerResponsePart<ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) {
    self.act(on: self.state.sendResponsePartFromInterceptors(part, promise: promise))
  }
}

// MARK: - State

extension _BaseCallHandler {
  fileprivate enum State {
    /// Idle. We're waiting to be added to a pipeline.
    case idle

    /// We're in a pipeline and receiving from the client.
    case active(ActiveState)

    /// We're done. This state is terminal, all actions are ignored.
    case closed
  }
}

extension _BaseCallHandler.State {
  /// The state of the request and response streams.
  ///
  /// We track the stream state twice: between the 'Channel' and interceptor pipeline, and between
  /// the interceptor pipeline and event observer.
  fileprivate enum StreamState {
    case requestIdleResponseIdle
    case requestOpenResponseIdle
    case requestOpenResponseOpen
    case requestClosedResponseIdle
    case requestClosedResponseOpen
    case requestClosedResponseClosed

    enum Filter {
      case allow
      case drop
    }

    mutating func receiveHeaders() -> Filter {
      switch self {
      case .requestIdleResponseIdle:
        self = .requestOpenResponseIdle
        return .allow

      case .requestOpenResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return .drop
      }
    }

    func receiveMessage() -> Filter {
      switch self {
      case .requestOpenResponseIdle,
           .requestOpenResponseOpen:
        return .allow

      case .requestIdleResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return .drop
      }
    }

    mutating func receiveEnd() -> Filter {
      switch self {
      case .requestOpenResponseIdle:
        self = .requestClosedResponseIdle
        return .allow

      case .requestOpenResponseOpen:
        self = .requestClosedResponseOpen
        return .allow

      case .requestIdleResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return .drop
      }
    }

    mutating func sendHeaders() -> Filter {
      switch self {
      case .requestOpenResponseIdle:
        self = .requestOpenResponseOpen
        return .allow

      case .requestClosedResponseIdle:
        self = .requestClosedResponseOpen
        return .allow

      case .requestIdleResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return .drop
      }
    }

    func sendMessage() -> Filter {
      switch self {
      case .requestOpenResponseOpen,
           .requestClosedResponseOpen:
        return .allow

      case .requestIdleResponseIdle,
           .requestOpenResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseClosed:
        return .drop
      }
    }

    mutating func sendEnd() -> Filter {
      switch self {
      case .requestIdleResponseIdle:
        return .drop

      case .requestOpenResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen:
        self = .requestClosedResponseClosed
        return .allow

      case .requestClosedResponseClosed:
        return .drop
      }
    }
  }

  fileprivate struct ActiveState {
    var context: ChannelHandlerContext

    /// The stream state between the 'Channel' and interceptor pipeline.
    var channelStreamState: StreamState

    /// The stream state between the interceptor pipeline and event observer.
    var observerStreamState: StreamState

    init(context: ChannelHandlerContext) {
      self.context = context
      self.channelStreamState = .requestIdleResponseIdle
      self.observerStreamState = .requestIdleResponseIdle
    }
  }
}

extension _BaseCallHandler.State {
  fileprivate enum Action {
    /// Do nothing.
    case none

    /// Receive the request part in the interceptor pipeline.
    case receiveRequestPartInInterceptors(GRPCServerRequestPart<_BaseCallHandler.RequestPayload>)

    /// Receive the request part in the observer.
    case receiveRequestPartInObserver(GRPCServerRequestPart<_BaseCallHandler.RequestPayload>)

    /// Receive an error in the observer.
    case receiveLibraryErrorInObserver(Error)

    /// Send a response part to the interceptor pipeline.
    case sendResponsePartToInterceptors(
      GRPCServerResponsePart<_BaseCallHandler.ResponsePayload>,
      EventLoopPromise<Void>?
    )

    /// Write the response part to the `Channel`.
    case writeResponsePartToChannel(
      ChannelHandlerContext,
      GRPCServerResponsePart<_BaseCallHandler.ResponsePayload>,
      promise: EventLoopPromise<Void>?
    )

    /// Complete the promise with the result.
    case completePromise(EventLoopPromise<Void>?, Result<Void, Error>)

    /// Perform multiple actions.
    indirect case multiple([Action])
  }
}

extension _BaseCallHandler.State {
  /// The handler was added to the `ChannelPipeline`: this is the only way to move from the `.idle`
  /// state. We only expect this to be called once.
  internal mutating func handlerAdded(context: ChannelHandlerContext) -> Action {
    switch self {
    case .idle:
      // This is the only way we can become active.
      self = .active(.init(context: context))
      return .none

    case .active:
      preconditionFailure("Invalid state: already active")

    case .closed:
      return .none
    }
  }

  /// Received an error from the `Channel`.
  internal mutating func errorCaught(_ error: Error) -> Action {
    switch self {
    case .active:
      return .receiveLibraryErrorInObserver(error)

    case .idle, .closed:
      return .none
    }
  }

  /// Receive a request part from the `Channel`. If we're active we just forward these through the
  /// pipeline. We validate at the other end.
  internal mutating func channelRead(
    _ requestPart: GRPCServerRequestPart<_BaseCallHandler.RequestPayload>
  ) -> Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")

    case var .active(state):
      // Avoid CoW-ing state.
      self = .idle

      let filter: StreamState.Filter
      let part: GRPCServerRequestPart<_BaseCallHandler.RequestPayload>

      switch requestPart {
      case let .metadata(headers):
        filter = state.channelStreamState.receiveHeaders()
        part = .metadata(headers)
      case let .message(message):
        filter = state.channelStreamState.receiveMessage()
        part = .message(message)
      case .end:
        filter = state.channelStreamState.receiveEnd()
        part = .end
      }

      // Restore state.
      self = .active(state)

      switch filter {
      case .allow:
        return .receiveRequestPartInInterceptors(part)
      case .drop:
        return .none
      }

    case .closed:
      return .none
    }
  }

  /// Send a response part from the observer to the interceptors.
  internal mutating func sendResponsePartFromObserver(
    _ part: GRPCServerResponsePart<_BaseCallHandler.ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) -> Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")

    case var .active(state):
      // Avoid CoW-ing 'state'.
      self = .idle

      let filter: StreamState.Filter

      switch part {
      case .metadata:
        filter = state.observerStreamState.sendHeaders()
      case .message:
        filter = state.observerStreamState.sendMessage()
      case .end:
        filter = state.observerStreamState.sendEnd()
      }

      // Restore the state.
      self = .active(state)

      switch filter {
      case .allow:
        return .sendResponsePartToInterceptors(part, promise)
      case .drop:
        return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))
      }

    case .closed:
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))
    }
  }

  /// Send a response part from the interceptors to the `Channel`.
  internal mutating func sendResponsePartFromInterceptors(
    _ part: GRPCServerResponsePart<_BaseCallHandler.ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) -> Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: can't send response on idle call")

    case var .active(state):
      // Avoid CoW-ing 'state'.
      self = .idle

      let filter: StreamState.Filter

      switch part {
      case .metadata:
        filter = state.channelStreamState.sendHeaders()
        self = .active(state)
      case .message:
        filter = state.channelStreamState.sendMessage()
        self = .active(state)
      case .end:
        filter = state.channelStreamState.sendEnd()
        // We're sending end, we're no longer active.
        self = .closed
      }

      switch filter {
      case .allow:
        return .writeResponsePartToChannel(state.context, part, promise: promise)
      case .drop:
        return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))
      }

    case .closed:
      // We're already closed, fail any promise.
      return .completePromise(promise, .failure(GRPCError.AlreadyComplete()))
    }
  }

  /// A request part has traversed the interceptor pipeline, now send it to the observer.
  internal mutating func receiveRequestPartFromInterceptors(
    _ part: GRPCServerRequestPart<_BaseCallHandler.RequestPayload>
  ) -> Action {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")

    case var .active(state):
      // Avoid CoW-ing `state`.
      self = .idle

      let filter: StreamState.Filter

      // Does the active state allow us to send this?
      switch part {
      case .metadata:
        filter = state.observerStreamState.receiveHeaders()
      case .message:
        filter = state.observerStreamState.receiveMessage()
      case .end:
        filter = state.observerStreamState.receiveEnd()
      }

      // Put `state` back.
      self = .active(state)

      switch filter {
      case .allow:
        return .receiveRequestPartInObserver(part)
      case .drop:
        return .none
      }

    case .closed:
      // We're closed, just ignore this.
      return .none
    }
  }
}

// MARK: State Actions

extension _BaseCallHandler {
  private func act(on action: State.Action) {
    switch action {
    case .none:
      ()

    case let .receiveRequestPartInInterceptors(part):
      self.receiveRequestPartInInterceptors(part)

    case let .receiveRequestPartInObserver(part):
      self.receiveRequestPartInObserver(part)

    case let .receiveLibraryErrorInObserver(error):
      self.observeLibraryError(error)

    case let .sendResponsePartToInterceptors(part, promise):
      self.sendResponsePartToInterceptors(part, promise: promise)

    case let .writeResponsePartToChannel(context, part, promise):
      self.writeResponsePartToChannel(context: context, part: part, promise: promise)

    case let .completePromise(promise, result):
      promise?.completeWith(result)

    case let .multiple(actions):
      for action in actions {
        self.act(on: action)
      }
    }
  }

  /// Receives a request part in the interceptor pipeline.
  private func receiveRequestPartInInterceptors(_ part: GRPCServerRequestPart<RequestPayload>) {
    self.pipeline?.receive(part)
  }

  /// Observe a request part. This just farms out to the subclass implementation for the
  /// appropriate part.
  private func receiveRequestPartInObserver(_ part: GRPCServerRequestPart<RequestPayload>) {
    switch part {
    case let .metadata(headers):
      self.observeHeaders(headers)
    case let .message(request):
      self.observeRequest(request)
    case .end:
      self.observeEnd()
    }
  }

  /// Sends a response part into the interceptor pipeline.
  private func sendResponsePartToInterceptors(
    _ part: GRPCServerResponsePart<ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) {
    if let pipeline = self.pipeline {
      pipeline.send(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Writes a response part to the `Channel`.
  private func writeResponsePartToChannel(
    context: ChannelHandlerContext,
    part: GRPCServerResponsePart<ResponsePayload>,
    promise: EventLoopPromise<Void>?
  ) {
    let flush: Bool

    switch part {
    case let .metadata(headers):
      // Only flush if we're streaming responses, if we're not streaming responses then we'll wait
      // for the response and end before emitting the flush.
      flush = self.callType.isStreamingResponses
      context.write(self.wrapOutboundOut(.metadata(headers)), promise: promise)

    case let .message(message, metadata):
      do {
        let serializedResponse = try self.responseSerializer.serialize(
          message,
          allocator: context.channel.allocator
        )
        context.write(
          self.wrapOutboundOut(.message(serializedResponse, metadata)),
          promise: promise
        )
        // Flush if we've been told to flush.
        flush = metadata.flush
      } catch {
        self.errorCaught(context: context, error: error)
        promise?.fail(error)
        return
      }

    case let .end(status, trailers):
      context.write(self.wrapOutboundOut(.end(status, trailers)), promise: promise)
      // Always flush on end.
      flush = true
    }

    if flush {
      context.flush()
    }
  }
}
