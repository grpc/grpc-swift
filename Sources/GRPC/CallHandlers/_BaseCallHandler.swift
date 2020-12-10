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

  /// The `ChannelHandlerContext`.
  private var context: ChannelHandlerContext?

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
    requestDeserializer: RequestDeserializer,
    responseSerializer: ResponseSerializer,
    callType: GRPCCallType,
    interceptors: [ServerInterceptor<RequestPayload, ResponsePayload>]
  ) {
    let userInfoRef = Ref(UserInfo())
    self.requestDeserializer = requestDeserializer
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
    self.state.handlerAdded()
    self.context = context
  }

  public func handlerRemoved(context: ChannelHandlerContext) {
    self.pipeline = nil
    self.context = nil
  }

  public func channelInactive(context: ChannelHandlerContext) {
    self.pipeline = nil
    context.fireChannelInactive()
  }

  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    if self.state.errorCaught() {
      self.observeLibraryError(error)
    }
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = self.unwrapInboundIn(data)

    switch part {
    case let .metadata(headers):
      if self.state.channelReadMetadata() {
        self.receiveRequestPartInInterceptors(.metadata(headers))
      }

    case let .message(buffer):
      if self.state.channelReadMessage() {
        do {
          let request = try self.requestDeserializer.deserialize(byteBuffer: buffer)
          self.receiveRequestPartInInterceptors(.message(request))
        } catch {
          self.errorCaught(context: context, error: error)
        }
      }

    case .end:
      if self.state.channelReadEnd() {
        self.receiveRequestPartInInterceptors(.end)
      }
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
    let forward: Bool

    switch part {
    case .metadata:
      forward = self.state.sendResponsePartFromObserver(.metadata)
    case .message:
      forward = self.state.sendResponsePartFromObserver(.message)
    case .end:
      forward = self.state.sendResponsePartFromObserver(.end)
    }

    if forward {
      self.sendResponsePartToInterceptors(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
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
    let forward: Bool

    switch part {
    case .metadata:
      forward = self.state.receiveRequestPartFromInterceptors(.metadata)
    case .message:
      forward = self.state.receiveRequestPartFromInterceptors(.message)
    case .end:
      forward = self.state.receiveRequestPartFromInterceptors(.end)
    }

    if forward {
      self.receiveRequestPartInObserver(part)
    }
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
    let forward: Bool

    switch part {
    case .metadata:
      forward = self.state.sendResponsePartFromInterceptors(.metadata)
    case .message:
      forward = self.state.sendResponsePartFromInterceptors(.message)
    case .end:
      forward = self.state.sendResponsePartFromInterceptors(.end)
    }

    if forward, let context = self.context {
      self.writeResponsePartToChannel(context: context, part: part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }
}

// MARK: - State

private enum State {
  /// Idle. We're waiting to be added to a pipeline.
  case idle

  /// We're in a pipeline and receiving from the client.
  case active(ActiveState)

  /// We're done. This state is terminal, all actions are ignored.
  case closed
}

private enum RPCStreamPart {
  case metadata
  case message
  case end
}

extension State {
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

    mutating func receiveHeaders() -> Bool {
      switch self {
      case .requestIdleResponseIdle:
        self = .requestOpenResponseIdle
        return true

      case .requestOpenResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return false
      }
    }

    func receiveMessage() -> Bool {
      switch self {
      case .requestOpenResponseIdle,
           .requestOpenResponseOpen:
        return true

      case .requestIdleResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return false
      }
    }

    mutating func receiveEnd() -> Bool {
      switch self {
      case .requestOpenResponseIdle:
        self = .requestClosedResponseIdle
        return true

      case .requestOpenResponseOpen:
        self = .requestClosedResponseOpen
        return true

      case .requestIdleResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return false
      }
    }

    mutating func sendHeaders() -> Bool {
      switch self {
      case .requestOpenResponseIdle:
        self = .requestOpenResponseOpen
        return true

      case .requestClosedResponseIdle:
        self = .requestClosedResponseOpen
        return true

      case .requestIdleResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseOpen,
           .requestClosedResponseClosed:
        return false
      }
    }

    func sendMessage() -> Bool {
      switch self {
      case .requestOpenResponseOpen,
           .requestClosedResponseOpen:
        return true

      case .requestIdleResponseIdle,
           .requestOpenResponseIdle,
           .requestClosedResponseIdle,
           .requestClosedResponseClosed:
        return false
      }
    }

    mutating func sendEnd() -> Bool {
      switch self {
      case .requestIdleResponseIdle:
        return false

      case .requestOpenResponseIdle,
           .requestOpenResponseOpen,
           .requestClosedResponseIdle,
           .requestClosedResponseOpen:
        self = .requestClosedResponseClosed
        return true

      case .requestClosedResponseClosed:
        return false
      }
    }
  }

  fileprivate struct ActiveState {
    /// The stream state between the 'Channel' and interceptor pipeline.
    var channelStreamState: StreamState

    /// The stream state between the interceptor pipeline and event observer.
    var observerStreamState: StreamState

    init() {
      self.channelStreamState = .requestIdleResponseIdle
      self.observerStreamState = .requestIdleResponseIdle
    }
  }
}

extension State {
  /// The handler was added to the `ChannelPipeline`: this is the only way to move from the `.idle`
  /// state. We only expect this to be called once.
  internal mutating func handlerAdded() {
    switch self {
    case .idle:
      // This is the only way we can become active.
      self = .active(.init())
    case .active:
      preconditionFailure("Invalid state: already active")
    case .closed:
      ()
    }
  }

  /// Received an error from the `Channel`.
  /// - Returns: True if the error should be forwarded to the error observer, or false if it should
  ///   be dropped.
  internal func errorCaught() -> Bool {
    switch self {
    case .active:
      return true
    case .idle, .closed:
      return false
    }
  }

  /// Receive a metadata part from the `Channel`.
  /// - Returns: True if the part should be forwarded to the interceptor pipeline, false otherwise.
  internal mutating func channelReadMetadata() -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")
    case var .active(state):
      let allow = state.channelStreamState.receiveHeaders()
      self = .active(state)
      return allow
    case .closed:
      return false
    }
  }

  /// Receive a message part from the `Channel`.
  /// - Returns: True if the part should be forwarded to the interceptor pipeline, false otherwise.
  internal func channelReadMessage() -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")
    case let .active(state):
      return state.channelStreamState.receiveMessage()
    case .closed:
      return false
    }
  }

  /// Receive an end-stream part from the `Channel`.
  /// - Returns: True if the part should be forwarded to the interceptor pipeline, false otherwise.
  internal mutating func channelReadEnd() -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")
    case var .active(state):
      let allow = state.channelStreamState.receiveEnd()
      self = .active(state)
      return allow
    case .closed:
      return false
    }
  }

  /// Send a response part from the observer to the interceptors.
  /// - Returns: True if the part should be forwarded to the interceptor pipeline, false otherwise.
  internal mutating func sendResponsePartFromObserver(_ part: RPCStreamPart) -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")

    case var .active(state):
      // Avoid CoW-ing 'state'.
      self = .idle

      let allow: Bool

      switch part {
      case .metadata:
        allow = state.observerStreamState.sendHeaders()
      case .message:
        allow = state.observerStreamState.sendMessage()
      case .end:
        allow = state.observerStreamState.sendEnd()
      }

      // Restore the state.
      self = .active(state)
      return allow

    case .closed:
      return false
    }
  }

  /// Send a response part from the interceptors to the `Channel`.
  /// - Returns: True if the part should be forwarded to the `Channel`, false otherwise.
  internal mutating func sendResponsePartFromInterceptors(_ part: RPCStreamPart) -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: can't send response on idle call")

    case var .active(state):
      // Avoid CoW-ing 'state'.
      self = .idle

      let allow: Bool

      switch part {
      case .metadata:
        allow = state.channelStreamState.sendHeaders()
        self = .active(state)
      case .message:
        allow = state.channelStreamState.sendMessage()
        self = .active(state)
      case .end:
        allow = state.channelStreamState.sendEnd()
        // We're sending end, we're no longer active.
        self = .closed
      }

      return allow

    case .closed:
      // We're already closed.
      return false
    }
  }

  /// A request part has traversed the interceptor pipeline, now send it to the observer.
  /// - Returns: True if the part should be forwarded to the observer, false otherwise.
  internal mutating func receiveRequestPartFromInterceptors(_ part: RPCStreamPart) -> Bool {
    switch self {
    case .idle:
      preconditionFailure("Invalid state: the handler isn't in the pipeline yet")

    case var .active(state):
      // Avoid CoW-ing `state`.
      self = .idle

      let allow: Bool

      // Does the active state allow us to send this?
      switch part {
      case .metadata:
        allow = state.observerStreamState.receiveHeaders()
      case .message:
        allow = state.observerStreamState.receiveMessage()
      case .end:
        allow = state.observerStreamState.receiveEnd()
      }

      // Put `state` back.
      self = .active(state)
      return allow

    case .closed:
      // We're closed, just ignore this.
      return false
    }
  }
}

// MARK: State Actions

extension _BaseCallHandler {
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
      // Only flush if we're not unary: if we're unary we'll wait for the response and end before
      // emitting the flush.
      flush = self.callType != .unary
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
