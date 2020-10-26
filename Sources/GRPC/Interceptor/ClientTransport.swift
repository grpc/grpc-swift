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
import NIO
import NIOHPACK
import NIOHTTP2

/// This class is the glue between a `NIO.Channel` and the `ClientInterceptorPipeline`. In fact
/// this object owns the interceptor pipeline and is also a `ChannelHandler`. The caller has very
/// little API to use on this class: they may configure the transport by adding it to a
/// `NIO.ChannelPipeline` with `configure(_:)`, send request parts via `send(_:promise:)` and
/// attempt to cancel the RPC with `cancel(promise:)`. Response parts – after traversing the
/// interceptor pipeline – are emitted to the `onResponsePart` callback supplied to the initializer.
///
/// In most instances the glue code is simple: transformations are applied to the request and
/// response types used by the interceptor pipeline and the `NIO.Channel`. In addition, the
/// transport keeps track of the state of the call and the `Channel`, taking appropriate action
/// when these change. This includes buffering request parts from the interceptor pipeline until
/// the `NIO.Channel` becomes active.
///
/// ### Thread Safety
///
/// This class is not thread safe. All methods **must** be executed on the transport's `eventLoop`.
@usableFromInline
internal final class ClientTransport<Request, Response> {
  /// The `EventLoop` this transport is running on.
  @usableFromInline
  internal let eventLoop: EventLoop

  /// The current state of the transport.
  private var state: State = .idle

  /// A promise for the underlying `Channel`. We'll succeed this when we transition to `active`
  /// and fail it when we transition to `closed`.
  private var channelPromise: EventLoopPromise<Channel>?

  // Note: initial capacity is 4 because it's a power of 2 and most calls are unary so will
  // have 3 parts.
  /// A buffer to store request parts and promises in before the channel has become active.
  private var writeBuffer = MarkedCircularBuffer<RequestAndPromise>(initialCapacity: 4)

  /// A request part and a promise.
  private struct RequestAndPromise {
    var request: ClientRequestPart<Request>
    var promise: EventLoopPromise<Void>?
  }

  /// Details about the call.
  internal let callDetails: CallDetails

  /// A logger.
  internal var logger: Logger {
    return self.callDetails.options.logger
  }

  /// Is the call streaming requests?
  private var isStreamingRequests: Bool {
    switch self.callDetails.type {
    case .unary, .serverStreaming:
      return false
    case .clientStreaming, .bidirectionalStreaming:
      return true
    }
  }

  // Our `NIO.Channel` will fire trailers and the `GRPCStatus` to us separately. It's more
  // convenient to have both at the same time when intercepting response parts. We'll hold on to the
  // trailers here and only forward them when we receive the status.
  private var trailers: HPACKHeaders?

  /// The interceptor pipeline connected to this transport. This must be set to `nil` when removed
  /// from the `ChannelPipeline` in order to break reference cycles.
  @usableFromInline
  internal var _pipeline: ClientInterceptorPipeline<Request, Response>?

  /// Our current state as logging metadata.
  private var stateForLogging: Logger.MetadataValue {
    if self.state.mayBuffer {
      return "\(self.state) (\(self.writeBuffer.count) parts buffered)"
    } else {
      return "\(self.state)"
    }
  }

  internal init(
    details: CallDetails,
    eventLoop: EventLoop,
    interceptors: [ClientInterceptor<Request, Response>],
    errorDelegate: ClientErrorDelegate?,
    _ onResponsePart: @escaping (ClientResponsePart<Response>) -> Void
  ) {
    self.eventLoop = eventLoop
    self.callDetails = details
    self._pipeline = ClientInterceptorPipeline(
      eventLoop: eventLoop,
      details: details,
      interceptors: interceptors,
      errorDelegate: errorDelegate,
      onCancel: self.cancelFromPipeline(promise:),
      onRequestPart: self.sendFromPipeline(_:promise:),
      onResponsePart: onResponsePart
    )
  }

  // MARK: - Call Object API

  /// Configure the transport to communicate with the server.
  /// - Parameter configurator: A callback to invoke in order to configure this transport.
  /// - Important: This *must* to be called from the `eventLoop`.
  internal func configure(_ configurator: @escaping (ChannelHandler) -> EventLoopFuture<Void>) {
    self.eventLoop.assertInEventLoop()
    self.act(on: self.state.configureTransport(with: configurator))
  }

  /// Send a request part – via the interceptor pipeline – to the server.
  /// - Parameters:
  ///   - part: The part to send.
  ///   - promise: A promise which will be completed when the request part has been handled.
  /// - Important: This *must* to be called from the `eventLoop`.
  @inlinable
  internal func send(_ part: ClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    if let pipeline = self._pipeline {
      pipeline.write(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Attempt to cancel the RPC notifying any interceptors.
  /// - Parameter promise: A promise which will be completed when the cancellation attempt has
  ///   been handled.
  internal func cancel(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    if let pipeline = self._pipeline {
      pipeline.cancel(promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// A request for the underlying `Channel`.
  internal func channel() -> EventLoopFuture<Channel> {
    self.eventLoop.assertInEventLoop()

    // Do we already have a promise?
    if let promise = self.channelPromise {
      return promise.futureResult
    } else {
      // Make and store the promise.
      let promise = self.eventLoop.makePromise(of: Channel.self)
      self.channelPromise = promise

      // Ask the state machine if we can have it.
      self.act(on: self.state.getChannel())

      return promise.futureResult
    }
  }
}

// MARK: - Pipeline API

extension ClientTransport {
  /// Sends a request part on the transport. Should only be called from the interceptor pipeline.
  /// - Parameters:
  ///   - part: The request part to send.
  ///   - promise: A promise which will be completed when the part has been handled.
  /// - Important: This *must* to be called from the `eventLoop`.
  private func sendFromPipeline(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.eventLoop.assertInEventLoop()
    self.act(on: self.state.send(part, promise: promise))
  }

  /// Attempt to cancel the RPC. Should only be called from the interceptor pipeline.
  /// - Parameter promise: A promise which will be completed when the cancellation has been handled.
  /// - Important: This *must* to be called from the `eventLoop`.
  private func cancelFromPipeline(promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()
    self.act(on: self.state.cancel(promise: promise))
  }
}

// MARK: - ChannelHandler API

extension ClientTransport: ChannelInboundHandler {
  @usableFromInline
  typealias InboundIn = _GRPCClientResponsePart<Response>

  @usableFromInline
  typealias OutboundOut = _GRPCClientRequestPart<Request>

  @usableFromInline
  internal func handlerRemoved(context: ChannelHandlerContext) {
    self.eventLoop.assertInEventLoop()
    // Break the reference cycle.
    self._pipeline = nil
  }

  internal func channelError(_ error: Error) {
    self.eventLoop.assertInEventLoop()
    self.act(on: self.state.channelError(error))
  }

  @usableFromInline
  internal func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.channelError(error)
  }

  @usableFromInline
  internal func channelActive(context: ChannelHandlerContext) {
    self.eventLoop.assertInEventLoop()
    self.logger.debug("activated stream channel", source: "GRPC")
    self.act(on: self.state.channelActive(context: context))
  }

  @usableFromInline
  internal func channelInactive(context: ChannelHandlerContext) {
    self.eventLoop.assertInEventLoop()
    self.act(on: self.state.channelInactive(context: context))
  }

  @usableFromInline
  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    self.eventLoop.assertInEventLoop()
    let part = self.unwrapInboundIn(data)
    self.act(on: self.state.channelRead(part))
    // (We're the end of the channel. No need to forward anything.)
  }
}

// MARK: - State Handling

extension ClientTransport {
  fileprivate enum State {
    /// Idle. We're waiting for the RPC to be configured.
    ///
    /// Valid transitions:
    /// - `awaitingTransport` (the transport is being configured)
    /// - `closed` (the RPC cancels)
    case idle

    /// Awaiting transport. The RPC has requested transport and we're waiting for that transport to
    /// activate. We'll buffer any outbound messages from this state. Receiving messages from the
    /// transport in this state is an error.
    ///
    /// Valid transitions:
    /// - `activatingTransport` (the channel becomes active)
    /// - `closing` (the RPC cancels)
    /// - `closed` (the channel fails to become active)
    case awaitingTransport

    /// The transport is active but we're unbuffering any requests to write on that transport.
    /// We'll continue buffering in this state. Receiving messages from the transport in this state
    /// is okay.
    ///
    /// Valid transitions:
    /// - `active` (we finish unbuffering)
    /// - `closing` (the RPC cancels, the channel encounters an error)
    /// - `closed` (the channel becomes inactive)
    case activatingTransport(Channel)

    /// Fully active. An RPC is in progress and is communicating over an active transport.
    ///
    /// Valid transitions:
    /// - `closing` (the RPC cancels, the channel encounters an error)
    /// - `closed` (the channel becomes inactive)
    case active(Channel)

    /// Closing. Either the RPC was cancelled or any `Channel` associated with the transport hasn't
    /// become inactive yet.
    ///
    /// Valid transitions:
    /// - `closed` (the channel becomes inactive)
    case closing

    /// We're closed. Any writes from the RPC will be failed. Any responses from the transport will
    /// be ignored.
    ///
    /// Valid transitions:
    /// - none: this state is terminal.
    case closed

    /// Whether writes may be unbuffered in this state.
    internal var isUnbuffering: Bool {
      switch self {
      case .activatingTransport:
        return true
      case .idle, .awaitingTransport, .active, .closing, .closed:
        return false
      }
    }

    /// Whether this state allows writes to be buffered. (This is useful only to inform logging.)
    internal var mayBuffer: Bool {
      switch self {
      case .idle, .activatingTransport, .awaitingTransport:
        return true
      case .active, .closing, .closed:
        return false
      }
    }
  }
}

extension ClientTransport.State {
  /// Actions which should be performed as a result telling the state machine something changed.
  fileprivate enum Action {
    /// Do nothing.
    case none

    /// Configure a `Channel` with the configurator.
    case configure(with: (ChannelHandler) -> EventLoopFuture<Void>)

    /// Append the request part and promise to the write buffer.
    case buffer(ClientRequestPart<Request>, EventLoopPromise<Void>?)

    /// Write - and flush if necessary – any request parts in the buffer to the `Channel`.
    case unbufferToChannel(Channel)

    /// Fail any buffered writes with the error.
    case failBufferedWrites(with: Error)

    /// Write the given operation to the channel.
    case writeToChannel(Channel, ClientRequestPart<Request>, EventLoopPromise<Void>?)

    /// Write the response part to the RPC.
    case forwardToInterceptors(_GRPCClientResponsePart<Response>)

    /// Fail the RPC with the given error. This includes failing any outstanding writes.
    case forwardErrorToInterceptors(Error)

    /// Close the given channel.
    case close(Channel)

    /// Fail the given promise with the error provided.
    case completePromise(EventLoopPromise<Void>?, with: Result<Void, Error>)

    /// Complete the lazy channel promise with this result.
    case completeChannelPromise(with: Result<Channel, Error>)

    /// Perform multiple actions.
    indirect case multiple([Action])
  }
}

extension ClientTransport.State {
  /// The caller would like to configure the transport.
  mutating func configureTransport(
    with configurator: @escaping (ChannelHandler) -> EventLoopFuture<Void>
  ) -> Action {
    switch self {
    // We're idle until we configure. Anything else is just a repeat request to configure.
    case .idle:
      self = .awaitingTransport
      return .configure(with: configurator)

    case .awaitingTransport, .activatingTransport, .active, .closing, .closed:
      return .none
    }
  }

  /// The pipeline would like to send a request part to the transport.
  mutating func send(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) -> Action {
    switch self {
    // We don't have any transport yet, just buffer the part.
    case .idle, .awaitingTransport, .activatingTransport:
      return .buffer(part, promise)

    // We have a `Channel`, we can pipe the write straight through.
    case let .active(channel):
      return .writeToChannel(channel, part, promise)

    // The transport is going or has gone away. Fail the promise.
    case .closing, .closed:
      return .completePromise(promise, with: .failure(GRPCError.AlreadyComplete()))
    }
  }

  /// We finished dealing with the buffered writes.
  mutating func unbuffered() -> Action {
    switch self {
    // These can't happen since we only begin unbuffering when we transition to
    // '.activatingTransport', which must come after these two states..
    case .idle, .awaitingTransport:
      preconditionFailure("Requests can't be unbuffered before the transport is activated")

    // We dealt with any buffered writes. We can become active now. This is the only way to become
    // active.
    case let .activatingTransport(channel):
      self = .active(channel)
      return .completeChannelPromise(with: .success(channel))

    case .active:
      preconditionFailure("Unbuffering completed but the transport is already active")

    // Something caused us to close while unbuffering, that's okay, we won't take any further
    // action.
    case .closing, .closed:
      return .none
    }
  }

  /// Cancel the RPC and associated `Channel`, if possible.
  mutating func cancel(promise: EventLoopPromise<Void>?) -> Action {
    switch self {
    case .idle:
      // No RPC has been started and we don't have a `Channel`. We need to tell the interceptor
      // we're done, fail any writes, and then deal with the cancellation promise.
      self = .closed
      let error = GRPCError.RPCCancelledByClient().captureContext()
      return .multiple([
        .forwardErrorToInterceptors(error),
        .failBufferedWrites(with: error.error),
        .completePromise(promise, with: .success(())),
        .completeChannelPromise(with: .failure(GRPCError.AlreadyComplete())),
      ])

    case .awaitingTransport:
      // An RPC has started and we're waiting for the `Channel` to activate. We'll mark ourselves as
      // closing. We don't need to explicitly close the `Channel`, this will happen as a result of
      // the `Channel` becoming active (see `channelActive(context:)`).
      self = .closing
      let error = GRPCError.RPCCancelledByClient().captureContext()
      return .multiple([
        .forwardErrorToInterceptors(error),
        .failBufferedWrites(with: error.error),
        .completePromise(promise, with: .success(())),
      ])

    case let .activatingTransport(channel):
      // The RPC has started, the `Channel` is active and we're emptying our write buffer. We'll
      // mark ourselves as closing: we'll error the interceptor pipeline, close the channel, fail
      // any buffered writes and then complete the cancellatiion promise.
      self = .closing
      let error = GRPCError.RPCCancelledByClient().captureContext()
      return .multiple([
        .forwardErrorToInterceptors(error),
        .close(channel),
        .failBufferedWrites(with: error.error),
        .completePromise(promise, with: .success(())),
      ])

    case let .active(channel):
      // The RPC and channel are up and running. We'll fail the RPC and close the channel.
      self = .closing
      let error = GRPCError.RPCCancelledByClient().captureContext()
      return .multiple([
        .forwardErrorToInterceptors(error),
        .close(channel),
        .completePromise(promise, with: .success(())),
      ])

    case .closing, .closed:
      // We're already closing or closing. The cancellation is too late.
      return .completePromise(promise, with: .failure(GRPCError.AlreadyComplete()))
    }
  }

  /// `channelActive` was invoked on the transport by the `Channel`.
  mutating func channelActive(context: ChannelHandlerContext) -> Action {
    // The channel has become active: what now?
    switch self {
    case .idle:
      preconditionFailure("Can't activate an idle transport")

    case .awaitingTransport:
      self = .activatingTransport(context.channel)
      return .unbufferToChannel(context.channel)

    case .activatingTransport, .active:
      preconditionFailure("Invalid state: stream is already active")

    case .closing:
      // We remain in closing: we only transition to closed on 'channelInactive'.
      return .close(context.channel)

    case .closed:
      preconditionFailure("Invalid state: stream is already inactive")
    }
  }

  /// `channelInactive` was invoked on the transport by the `Channel`.
  mutating func channelInactive(context: ChannelHandlerContext) -> Action {
    switch self {
    case .idle:
      // We can't become inactive before we've requested a `Channel`.
      preconditionFailure("Can't deactivate an idle transport")

    case .awaitingTransport, .activatingTransport, .active:
      // We're activating the transport - i.e. offloading any buffered requests - and the channel
      // became inactive. We haven't received an error (otherwise we'd be `closing`) so we should
      // synthesize an error status to fail the RPC with.
      self = .closed
      let status = GRPCStatus(code: .unavailable, message: "Transport became inactive")
      return .multiple([
        .forwardErrorToInterceptors(status),
        .failBufferedWrites(with: status),
        .completeChannelPromise(with: .failure(status)),
      ])

    case .closing:
      // We were already closing, now we're fully closed.
      self = .closed
      return .completeChannelPromise(with: .failure(GRPCError.AlreadyComplete()))

    case .closed:
      // We're already closed.
      return .none
    }
  }

  /// `channelRead` was invoked on the transport by the `Channel`.
  mutating func channelRead(_ part: _GRPCClientResponsePart<Response>) -> Action {
    switch self {
    case .idle, .awaitingTransport:
      // If there's no `Channel` or the `Channel` isn't active, then we can't read anything.
      preconditionFailure("Can't receive response part on idle transport")

    case .activatingTransport, .active:
      // We have an active `Channel`, we can forward the request part but we may need to start
      // closing if we see the status, since it indicates the call is terminating.
      switch part {
      case .initialMetadata, .message, .trailingMetadata:
        ()
      case .status:
        // The status is the final part of the RPC. We will become inactive soon.
        self = .closing
      }
      return .forwardToInterceptors(part)

    case .closing, .closed:
      // We closed early, ignore are reads.
      return .none
    }
  }

  /// We received an error from the `Channel`.
  mutating func channelError(_ error: Error) -> Action {
    switch self {
    case .idle:
      // The `Channel` can't error if it doesn't exist.
      preconditionFailure("Can't catch error on idle transport")

    case .awaitingTransport:
      // We're waiting for the `Channel` to become active. We're toast now, so close, failing any
      // buffered writes along the way.
      self = .closing
      return .multiple([
        .forwardErrorToInterceptors(error),
        .failBufferedWrites(with: error),
      ])

    case let .activatingTransport(channel),
         let .active(channel):
      // We're either fully active or unbuffering. Forward an error, fail any writes and then close.
      self = .closing
      return .multiple([
        .forwardErrorToInterceptors(error),
        .failBufferedWrites(with: error),
        .close(channel),
      ])

    case .closing, .closed:
      // We're already closing/closed, we can ignore this.
      return .none
    }
  }

  /// The caller has asked for the underlying `Channel`.
  mutating func getChannel() -> Action {
    switch self {
    case .idle, .awaitingTransport, .activatingTransport:
      // Do nothing, we'll complete the promise when we become active or closed.
      return .none

    case let .active(channel):
      // We're already active, so there was no promise to succeed when we made this transition. We
      // can complete it now.
      return .completeChannelPromise(with: .success(channel))

    case .closing:
      // We'll complete the promise when we transition to closed.
      return .none

    case .closed:
      // We're already closed; there was no promise to fail when we made this transition. We can go
      // ahead and fail it now though.
      return .completeChannelPromise(with: .failure(GRPCError.AlreadyComplete()))
    }
  }
}

// MARK: - State Actions

extension ClientTransport {
  /// Act on the action which resulted from prodding the state machine.
  /// - Parameter action: The action to act on.
  private func act(on action: State.Action) {
    switch action {
    case .none:
      ()

    case let .configure(configurator):
      self.configure(using: configurator)

    case let .buffer(part, promise):
      self.buffer(part, promise: promise)

    case let .unbufferToChannel(channel):
      self.unbuffer(to: channel)

    case let .failBufferedWrites(with: error):
      self.failBufferedWrites(with: error)

    case let .writeToChannel(channel, part, promise):
      self.write(part, to: channel, promise: promise, flush: self.shouldFlush(after: part))

    case let .forwardToInterceptors(response: part):
      self.forwardToInterceptors(part)

    case let .forwardErrorToInterceptors(error: error):
      self.forwardErrorToInterceptors(error)

    case let .completePromise(promise, result):
      promise?.completeWith(result)

    case let .completeChannelPromise(result):
      self.channelPromise?.completeWith(result)

    case let .close(channel):
      channel.close(mode: .all, promise: nil)

    case let .multiple(actions):
      for action in actions {
        self.act(on: action)
      }
    }
  }

  /// Configures this transport with the `configurator`.
  private func configure(using configurator: (ChannelHandler) -> EventLoopFuture<Void>) {
    configurator(self).whenFailure { error in
      if error is GRPCStatus || error is GRPCStatusTransformable {
        self.channelError(error)
      } else {
        // Fallback to something which will mark the RPC as 'unavailable'.
        self.channelError(ConnectionFailure(reason: error))
      }
    }
  }

  /// Append a request part to the write buffer.
  /// - Parameters:
  ///   - part: The request part to buffer.
  ///   - promise: A promise to complete when the request part has been sent.
  private func buffer(
    _ part: ClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.logger.debug("buffering request part", metadata: [
      "request_part": "\(part.name)",
      "call_state": self.stateForLogging,
    ], source: "GRPC")
    self.writeBuffer.append(.init(request: part, promise: promise))
  }

  /// Writes any buffered request parts to the `Channel`.
  /// - Parameter channel: The `Channel` to write any buffered request parts to.
  private func unbuffer(to channel: Channel) {
    // Save any flushing until we're done writing.
    var shouldFlush = false

    self.logger.debug("unbuffering request parts", metadata: [
      "request_parts": "\(self.writeBuffer.count)",
    ], source: "GRPC")

    // Why the double loop? A promise completed as a result of the flush may enqueue more writes,
    // or causes us to change state (i.e. we may have to close). If we didn't loop around then we
    // may miss more buffered writes.
    while self.state.isUnbuffering, !self.writeBuffer.isEmpty {
      // Pull out as many writes as possible.
      while let write = self.writeBuffer.popFirst() {
        self.logger.debug("unbuffering request part", metadata: [
          "request_part": "\(write.request.name)",
        ], source: "GRPC")

        if !shouldFlush {
          shouldFlush = self.shouldFlush(after: write.request)
        }

        self.write(write.request, to: channel, promise: write.promise, flush: false)
      }

      // Okay, flush now.
      if shouldFlush {
        shouldFlush = false
        channel.flush()
      }
    }

    if self.writeBuffer.isEmpty {
      self.logger.debug("request buffer drained", source: "GRPC")
    } else {
      self.logger.notice(
        "unbuffering aborted",
        metadata: ["call_state": self.stateForLogging],
        source: "GRPC"
      )
    }

    // We're unbuffered. What now?
    self.act(on: self.state.unbuffered())
  }

  /// Fails any promises that come with buffered writes with `error`.
  /// - Parameter error: The `Error` to fail promises with.
  private func failBufferedWrites(with error: Error) {
    self.logger.debug("failing buffered writes", metadata: [
      "call_state": self.stateForLogging,
    ], source: "GRPC")

    while let write = self.writeBuffer.popFirst() {
      write.promise?.fail(error)
    }
  }

  /// Write a request part to the `Channel`.
  /// - Parameters:
  ///   - part: The request part to write.
  ///   - channel: The `Channel` to write `part` in to.
  ///   - promise: A promise to complete once the write has been completed.
  ///   - flush: Whether to flush the `Channel` after writing.
  private func write(
    _ part: ClientRequestPart<Request>,
    to channel: Channel,
    promise: EventLoopPromise<Void>?,
    flush: Bool
  ) {
    switch part {
    case let .metadata(headers):
      let head = self.makeRequestHead(with: headers)
      channel.write(self.wrapOutboundOut(.head(head)), promise: promise)

    case let .message(request, metadata):
      let message = _MessageContext<Request>(request, compressed: metadata.compress)
      channel.write(self.wrapOutboundOut(.message(message)), promise: promise)

    case .end:
      channel.write(self.wrapOutboundOut(.end), promise: promise)
    }

    if flush {
      channel.flush()
    }
  }

  /// Forward the response part to the interceptor pipeline.
  /// - Parameter part: The response part to forward.
  private func forwardToInterceptors(_ part: _GRPCClientResponsePart<Response>) {
    switch part {
    case let .initialMetadata(metadata):
      self._pipeline?.read(.metadata(metadata))

    case let .message(context):
      self._pipeline?.read(.message(context.message))

    case let .trailingMetadata(trailers):
      // The `Channel` delivers trailers and `GRPCStatus`, we want to emit them together in the
      // interceptor pipeline.
      self.trailers = trailers

    case let .status(status):
      let trailers = self.trailers ?? [:]
      self.trailers = nil
      self._pipeline?.read(.end(status, trailers))
    }
  }

  /// Forward the error to the interceptor pipeline.
  /// - Parameter error: The error to forward.
  private func forwardErrorToInterceptors(_ error: Error) {
    self._pipeline?.read(.error(error))
  }
}

// MARK: - Helpers

extension ClientTransport {
  /// Returns whether the `Channel` should be flushed after writing the given part to it.
  private func shouldFlush(after part: ClientRequestPart<Request>) -> Bool {
    switch part {
    case .metadata:
      // If we're not streaming requests then we hold off on the flush until we see end.
      return self.isStreamingRequests

    case let .message(_, metadata):
      // Message flushing is determined by caller preference.
      return metadata.flush

    case .end:
      // Always flush at the end of the request stream.
      return true
    }
  }

  /// Make a `_GRPCRequestHead` with the provided metadata.
  private func makeRequestHead(with metadata: HPACKHeaders) -> _GRPCRequestHead {
    return _GRPCRequestHead(
      method: self.callDetails.options.cacheable ? "GET" : "POST",
      scheme: self.callDetails.scheme,
      path: self.callDetails.path,
      host: self.callDetails.authority,
      deadline: self.callDetails.options.timeLimit.makeDeadline(),
      customMetadata: metadata,
      encoding: self.callDetails.options.messageEncoding
    )
  }
}

extension ClientRequestPart {
  /// The name of the request part, used for logging.
  fileprivate var name: String {
    switch self {
    case .metadata:
      return "metadata"
    case .message:
      return "message"
    case .end:
      return "end"
    }
  }
}
