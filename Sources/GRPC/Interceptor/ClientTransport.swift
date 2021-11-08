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
/// This class is not thread safe. All methods **must** be executed on the transport's `callEventLoop`.
@usableFromInline
internal final class ClientTransport<Request, Response> {
  /// The `EventLoop` the call is running on. State must be accessed from this event loop.
  @usableFromInline
  internal let callEventLoop: EventLoop

  /// The current state of the transport.
  private var state: ClientTransportState = .idle

  /// A promise for the underlying `Channel`. We'll succeed this when we transition to `active`
  /// and fail it when we transition to `closed`.
  private var channelPromise: EventLoopPromise<Channel>?

  // Note: initial capacity is 4 because it's a power of 2 and most calls are unary so will
  // have 3 parts.
  /// A buffer to store request parts and promises in before the channel has become active.
  private var writeBuffer = MarkedCircularBuffer<RequestAndPromise>(initialCapacity: 4)

  /// The request serializer.
  private let serializer: AnySerializer<Request>

  /// The response deserializer.
  private let deserializer: AnyDeserializer<Response>

  /// A request part and a promise.
  private struct RequestAndPromise {
    var request: GRPCClientRequestPart<Request>
    var promise: EventLoopPromise<Void>?
  }

  /// Details about the call.
  internal let callDetails: CallDetails

  /// A logger.
  internal var logger: GRPCLogger

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

  /// The interceptor pipeline connected to this transport. The pipeline also holds references
  /// to `self` which are dropped when the interceptor pipeline is closed.
  @usableFromInline
  internal var _pipeline: ClientInterceptorPipeline<Request, Response>?

  /// The `NIO.Channel` used by the transport, if it is available.
  private var channel: Channel?

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
    serializer: AnySerializer<Request>,
    deserializer: AnyDeserializer<Response>,
    errorDelegate: ClientErrorDelegate?,
    onError: @escaping (Error) -> Void,
    onResponsePart: @escaping (GRPCClientResponsePart<Response>) -> Void
  ) {
    self.callEventLoop = eventLoop
    self.callDetails = details
    let logger = GRPCLogger(wrapping: details.options.logger)
    self.logger = logger
    self.serializer = serializer
    self.deserializer = deserializer
    // The references to self held by the pipeline are dropped when it is closed.
    self._pipeline = ClientInterceptorPipeline(
      eventLoop: eventLoop,
      details: details,
      logger: logger,
      interceptors: interceptors,
      errorDelegate: errorDelegate,
      onError: onError,
      onCancel: self.cancelFromPipeline(promise:),
      onRequestPart: self.sendFromPipeline(_:promise:),
      onResponsePart: onResponsePart
    )
  }

  // MARK: - Call Object API

  /// Configure the transport to communicate with the server.
  /// - Parameter configurator: A callback to invoke in order to configure this transport.
  /// - Important: This *must* to be called from the `callEventLoop`.
  internal func configure(_ configurator: @escaping (ChannelHandler) -> EventLoopFuture<Void>) {
    self.callEventLoop.assertInEventLoop()
    if self.state.configureTransport() {
      self.configure(using: configurator)
    }
  }

  /// Send a request part – via the interceptor pipeline – to the server.
  /// - Parameters:
  ///   - part: The part to send.
  ///   - promise: A promise which will be completed when the request part has been handled.
  /// - Important: This *must* to be called from the `callEventLoop`.
  @inlinable
  internal func send(_ part: GRPCClientRequestPart<Request>, promise: EventLoopPromise<Void>?) {
    self.callEventLoop.assertInEventLoop()
    if let pipeline = self._pipeline {
      pipeline.send(part, promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Attempt to cancel the RPC notifying any interceptors.
  /// - Parameter promise: A promise which will be completed when the cancellation attempt has
  ///   been handled.
  internal func cancel(promise: EventLoopPromise<Void>?) {
    self.callEventLoop.assertInEventLoop()
    if let pipeline = self._pipeline {
      pipeline.cancel(promise: promise)
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// A request for the underlying `Channel`.
  internal func getChannel() -> EventLoopFuture<Channel> {
    self.callEventLoop.assertInEventLoop()

    // Do we already have a promise?
    if let promise = self.channelPromise {
      return promise.futureResult
    } else {
      // Make and store the promise.
      let promise = self.callEventLoop.makePromise(of: Channel.self)
      self.channelPromise = promise

      // Ask the state machine if we can have it.
      switch self.state.getChannel() {
      case .succeed:
        if let channel = self.channel {
          promise.succeed(channel)
        }

      case .fail:
        promise.fail(GRPCError.AlreadyComplete())

      case .doNothing:
        ()
      }

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
  /// - Important: This *must* to be called from the `callEventLoop`.
  private func sendFromPipeline(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.callEventLoop.assertInEventLoop()
    switch self.state.send() {
    case .writeToBuffer:
      self.buffer(part, promise: promise)

    case .writeToChannel:
      // Banging the channel is okay here: we'll only be told to 'writeToChannel' if we're in the
      // correct state, the requirements of that state are having an active `Channel`.
      self.writeToChannel(
        self.channel!,
        part: part,
        promise: promise,
        flush: self.shouldFlush(after: part)
      )

    case .alreadyComplete:
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Attempt to cancel the RPC. Should only be called from the interceptor pipeline.
  /// - Parameter promise: A promise which will be completed when the cancellation has been handled.
  /// - Important: This *must* to be called from the `callEventLoop`.
  private func cancelFromPipeline(promise: EventLoopPromise<Void>?) {
    self.callEventLoop.assertInEventLoop()

    if self.state.cancel() {
      let error = GRPCError.RPCCancelledByClient()
      let status = error.makeGRPCStatus()
      self.forwardToInterceptors(.end(status, [:]))
      self.failBufferedWrites(with: error)
      self.channel?.close(mode: .all, promise: nil)
      self.channelPromise?.fail(error)
      promise?.succeed(())
    } else {
      promise?.fail(GRPCError.AlreadyComplete())
    }
  }
}

// MARK: - ChannelHandler API

extension ClientTransport: ChannelInboundHandler {
  @usableFromInline
  typealias InboundIn = _RawGRPCClientResponsePart

  @usableFromInline
  typealias OutboundOut = _RawGRPCClientRequestPart

  @usableFromInline
  internal func handlerRemoved(context: ChannelHandlerContext) {
    self.dropReferences()
  }

  @usableFromInline
  internal func handlerAdded(context: ChannelHandlerContext) {
    if context.channel.isActive {
      self.transportActivated(channel: context.channel)
    }
  }

  @usableFromInline
  internal func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.handleError(error)
  }

  @usableFromInline
  internal func channelActive(context: ChannelHandlerContext) {
    self.transportActivated(channel: context.channel)
  }

  @usableFromInline
  internal func channelInactive(context: ChannelHandlerContext) {
    self.transportDeactivated()
  }

  @usableFromInline
  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case let .initialMetadata(headers):
      self.receiveFromChannel(initialMetadata: headers)

    case let .message(box):
      self.receiveFromChannel(message: box.message)

    case let .trailingMetadata(trailers):
      self.receiveFromChannel(trailingMetadata: trailers)

    case let .status(status):
      self.receiveFromChannel(status: status)
    }

    // (We're the end of the channel. No need to forward anything.)
  }
}

extension ClientTransport {
  /// The `Channel` became active. Send out any buffered requests.
  private func transportActivated(channel: Channel) {
    if self.callEventLoop.inEventLoop {
      self._transportActivated(channel: channel)
    } else {
      self.callEventLoop.execute {
        self._transportActivated(channel: channel)
      }
    }
  }

  /// On-loop implementation of `transportActivated(channel:)`.
  private func _transportActivated(channel: Channel) {
    self.callEventLoop.assertInEventLoop()

    switch self.state.activate() {
    case .unbuffer:
      self.logger.addIPAddressMetadata(local: channel.localAddress, remote: channel.remoteAddress)
      self._pipeline?.logger = self.logger
      self.logger.debug("activated stream channel")
      self.channel = channel
      self.unbuffer()

    case .close:
      channel.close(mode: .all, promise: nil)

    case .doNothing:
      ()
    }
  }

  /// The `Channel` became inactive. Fail any buffered writes and forward an error to the
  /// interceptor pipeline if necessary.
  private func transportDeactivated() {
    if self.callEventLoop.inEventLoop {
      self._transportDeactivated()
    } else {
      self.callEventLoop.execute {
        self._transportDeactivated()
      }
    }
  }

  /// On-loop implementation of `transportDeactivated()`.
  private func _transportDeactivated() {
    self.callEventLoop.assertInEventLoop()
    switch self.state.deactivate() {
    case .doNothing:
      ()

    case .tearDown:
      let status = GRPCStatus(code: .unavailable, message: "Transport became inactive")
      self.forwardErrorToInterceptors(status)
      self.failBufferedWrites(with: status)
      self.channelPromise?.fail(status)

    case .failChannelPromise:
      self.channelPromise?.fail(GRPCError.AlreadyComplete())
    }
  }

  /// Drops any references to the `Channel` and interceptor pipeline.
  private func dropReferences() {
    if self.callEventLoop.inEventLoop {
      self.channel = nil
    } else {
      self.callEventLoop.execute {
        self.channel = nil
      }
    }
  }

  /// Handles an error caught in the pipeline or from elsewhere. The error may be forwarded to the
  /// interceptor pipeline and any buffered writes will be failed. Any underlying `Channel` will
  /// also be closed.
  internal func handleError(_ error: Error) {
    if self.callEventLoop.inEventLoop {
      self._handleError(error)
    } else {
      self.callEventLoop.execute {
        self._handleError(error)
      }
    }
  }

  /// On-loop implementation of `handleError(_:)`.
  private func _handleError(_ error: Error) {
    self.callEventLoop.assertInEventLoop()

    switch self.state.handleError() {
    case .doNothing:
      ()

    case .propagateError:
      self.forwardErrorToInterceptors(error)
      self.failBufferedWrites(with: error)

    case .propagateErrorAndClose:
      self.forwardErrorToInterceptors(error)
      self.failBufferedWrites(with: error)
      self.channel?.close(mode: .all, promise: nil)
    }
  }

  /// Receive initial metadata from the `Channel`.
  private func receiveFromChannel(initialMetadata headers: HPACKHeaders) {
    if self.callEventLoop.inEventLoop {
      self._receiveFromChannel(initialMetadata: headers)
    } else {
      self.callEventLoop.execute {
        self._receiveFromChannel(initialMetadata: headers)
      }
    }
  }

  /// On-loop implementation of `receiveFromChannel(initialMetadata:)`.
  private func _receiveFromChannel(initialMetadata headers: HPACKHeaders) {
    self.callEventLoop.assertInEventLoop()
    if self.state.channelRead(isEnd: false) {
      self.forwardToInterceptors(.metadata(headers))
    }
  }

  /// Receive response message bytes from the `Channel`.
  private func receiveFromChannel(message buffer: ByteBuffer) {
    if self.callEventLoop.inEventLoop {
      self._receiveFromChannel(message: buffer)
    } else {
      self.callEventLoop.execute {
        self._receiveFromChannel(message: buffer)
      }
    }
  }

  /// On-loop implementation of `receiveFromChannel(message:)`.
  private func _receiveFromChannel(message buffer: ByteBuffer) {
    self.callEventLoop.assertInEventLoop()
    do {
      let message = try self.deserializer.deserialize(byteBuffer: buffer)
      if self.state.channelRead(isEnd: false) {
        self.forwardToInterceptors(.message(message))
      }
    } catch {
      self.handleError(error)
    }
  }

  /// Receive trailing metadata from the `Channel`.
  private func receiveFromChannel(trailingMetadata trailers: HPACKHeaders) {
    // The `Channel` delivers trailers and `GRPCStatus` separately, we want to emit them together
    // in the interceptor pipeline.
    if self.callEventLoop.inEventLoop {
      self.trailers = trailers
    } else {
      self.callEventLoop.execute {
        self.trailers = trailers
      }
    }
  }

  /// Receive the final status from the `Channel`.
  private func receiveFromChannel(status: GRPCStatus) {
    if self.callEventLoop.inEventLoop {
      self._receiveFromChannel(status: status)
    } else {
      self.callEventLoop.execute {
        self._receiveFromChannel(status: status)
      }
    }
  }

  /// On-loop implementation of `receiveFromChannel(status:)`.
  private func _receiveFromChannel(status: GRPCStatus) {
    self.callEventLoop.assertInEventLoop()
    if self.state.channelRead(isEnd: true) {
      self.forwardToInterceptors(.end(status, self.trailers ?? [:]))
      self.trailers = nil
    }
  }
}

// MARK: - State Handling

private enum ClientTransportState {
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
  case activatingTransport

  /// Fully active. An RPC is in progress and is communicating over an active transport.
  ///
  /// Valid transitions:
  /// - `closing` (the RPC cancels, the channel encounters an error)
  /// - `closed` (the channel becomes inactive)
  case active

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

extension ClientTransportState {
  /// The caller would like to configure the transport. Returns a boolean indicating whether we
  /// should configure it or not.
  mutating func configureTransport() -> Bool {
    switch self {
    // We're idle until we configure. Anything else is just a repeat request to configure.
    case .idle:
      self = .awaitingTransport
      return true

    case .awaitingTransport, .activatingTransport, .active, .closing, .closed:
      return false
    }
  }

  enum SendAction {
    /// Write the request into the buffer.
    case writeToBuffer
    /// Write the request into the channel.
    case writeToChannel
    /// The RPC has already completed, fail any promise associated with the write.
    case alreadyComplete
  }

  /// The pipeline would like to send a request part to the transport.
  mutating func send() -> SendAction {
    switch self {
    // We don't have any transport yet, just buffer the part.
    case .idle, .awaitingTransport, .activatingTransport:
      return .writeToBuffer

    // We have a `Channel`, we can pipe the write straight through.
    case .active:
      return .writeToChannel

    // The transport is going or has gone away. Fail the promise.
    case .closing, .closed:
      return .alreadyComplete
    }
  }

  enum UnbufferedAction {
    /// Nothing needs to be done.
    case doNothing
    /// Succeed the channel promise associated with the transport.
    case succeedChannelPromise
  }

  /// We finished dealing with the buffered writes.
  mutating func unbuffered() -> UnbufferedAction {
    switch self {
    // These can't happen since we only begin unbuffering when we transition to
    // '.activatingTransport', which must come after these two states..
    case .idle, .awaitingTransport:
      preconditionFailure("Requests can't be unbuffered before the transport is activated")

    // We dealt with any buffered writes. We can become active now. This is the only way to become
    // active.
    case .activatingTransport:
      self = .active
      return .succeedChannelPromise

    case .active:
      preconditionFailure("Unbuffering completed but the transport is already active")

    // Something caused us to close while unbuffering, that's okay, we won't take any further
    // action.
    case .closing, .closed:
      return .doNothing
    }
  }

  /// Cancel the RPC and associated `Channel`, if possible. Returns a boolean indicated whether
  /// cancellation can go ahead (and also whether the channel should be torn down).
  mutating func cancel() -> Bool {
    switch self {
    case .idle:
      // No RPC has been started and we don't have a `Channel`. We need to tell the interceptor
      // we're done, fail any writes, and then deal with the cancellation promise.
      self = .closed
      return true

    case .awaitingTransport:
      // An RPC has started and we're waiting for the `Channel` to activate. We'll mark ourselves as
      // closing. We don't need to explicitly close the `Channel`, this will happen as a result of
      // the `Channel` becoming active (see `channelActive(context:)`).
      self = .closing
      return true

    case .activatingTransport:
      // The RPC has started, the `Channel` is active and we're emptying our write buffer. We'll
      // mark ourselves as closing: we'll error the interceptor pipeline, close the channel, fail
      // any buffered writes and then complete the cancellation promise.
      self = .closing
      return true

    case .active:
      // The RPC and channel are up and running. We'll fail the RPC and close the channel.
      self = .closing
      return true

    case .closing, .closed:
      // We're already closing or closing. The cancellation is too late.
      return false
    }
  }

  enum ActivateAction {
    case unbuffer
    case close
    case doNothing
  }

  /// `channelActive` was invoked on the transport by the `Channel`.
  mutating func activate() -> ActivateAction {
    // The channel has become active: what now?
    switch self {
    case .idle:
      preconditionFailure("Can't activate an idle transport")

    case .awaitingTransport:
      self = .activatingTransport
      return .unbuffer

    case .activatingTransport, .active:
      // Already activated.
      return .doNothing

    case .closing:
      // We remain in closing: we only transition to closed on 'channelInactive'.
      return .close

    case .closed:
      preconditionFailure("Invalid state: stream is already inactive")
    }
  }

  enum ChannelInactiveAction {
    /// Tear down the transport; forward an error to the interceptors and fail any buffered writes.
    case tearDown
    /// Fail the 'Channel' promise, if one exists; the RPC is already complete.
    case failChannelPromise
    /// Do nothing.
    case doNothing
  }

  /// `channelInactive` was invoked on the transport by the `Channel`.
  mutating func deactivate() -> ChannelInactiveAction {
    switch self {
    case .idle:
      // We can't become inactive before we've requested a `Channel`.
      preconditionFailure("Can't deactivate an idle transport")

    case .awaitingTransport, .activatingTransport, .active:
      // We're activating the transport - i.e. offloading any buffered requests - and the channel
      // became inactive. We haven't received an error (otherwise we'd be `closing`) so we should
      // synthesize an error status to fail the RPC with.
      self = .closed
      return .tearDown

    case .closing:
      // We were already closing, now we're fully closed.
      self = .closed
      return .failChannelPromise

    case .closed:
      // We're already closed.
      return .doNothing
    }
  }

  /// `channelRead` was invoked on the transport by the `Channel`. Returns a boolean value
  /// indicating whether the part that was read should be forwarded to the interceptor pipeline.
  mutating func channelRead(isEnd: Bool) -> Bool {
    switch self {
    case .idle, .awaitingTransport:
      // If there's no `Channel` or the `Channel` isn't active, then we can't read anything.
      preconditionFailure("Can't receive response part on idle transport")

    case .activatingTransport, .active:
      // We have an active `Channel`, we can forward the request part but we may need to start
      // closing if we see the status, since it indicates the call is terminating.
      if isEnd {
        self = .closing
      }
      return true

    case .closing, .closed:
      // We closed early, ignore any reads.
      return false
    }
  }

  enum HandleErrorAction {
    /// Propagate the error to the interceptor pipeline and fail any buffered writes.
    case propagateError
    /// As above, but close the 'Channel' as well.
    case propagateErrorAndClose
    /// No action is required.
    case doNothing
  }

  /// An error was caught.
  mutating func handleError() -> HandleErrorAction {
    switch self {
    case .idle:
      // The `Channel` can't error if it doesn't exist.
      preconditionFailure("Can't catch error on idle transport")

    case .awaitingTransport:
      // We're waiting for the `Channel` to become active. We're toast now, so close, failing any
      // buffered writes along the way.
      self = .closing
      return .propagateError

    case .activatingTransport,
         .active:
      // We're either fully active or unbuffering. Forward an error, fail any writes and then close.
      self = .closing
      return .propagateErrorAndClose

    case .closing, .closed:
      // We're already closing/closed, we can ignore this.
      return .doNothing
    }
  }

  enum GetChannelAction {
    /// No action is required.
    case doNothing
    /// Succeed the Channel promise.
    case succeed
    /// Fail the 'Channel' promise, the RPC is already complete.
    case fail
  }

  /// The caller has asked for the underlying `Channel`.
  mutating func getChannel() -> GetChannelAction {
    switch self {
    case .idle, .awaitingTransport, .activatingTransport:
      // Do nothing, we'll complete the promise when we become active or closed.
      return .doNothing

    case .active:
      // We're already active, so there was no promise to succeed when we made this transition. We
      // can complete it now.
      return .succeed

    case .closing:
      // We'll complete the promise when we transition to closed.
      return .doNothing

    case .closed:
      // We're already closed; there was no promise to fail when we made this transition. We can go
      // ahead and fail it now though.
      return .fail
    }
  }
}

// MARK: - State Actions

extension ClientTransport {
  /// Configures this transport with the `configurator`.
  private func configure(using configurator: (ChannelHandler) -> EventLoopFuture<Void>) {
    configurator(self).whenFailure { error in
      // We might be on a different EL, but `handleError` will sort that out for us, so no need to
      // hop.
      if error is GRPCStatus || error is GRPCStatusTransformable {
        self.handleError(error)
      } else {
        // Fallback to something which will mark the RPC as 'unavailable'.
        self.handleError(ConnectionFailure(reason: error))
      }
    }
  }

  /// Append a request part to the write buffer.
  /// - Parameters:
  ///   - part: The request part to buffer.
  ///   - promise: A promise to complete when the request part has been sent.
  private func buffer(
    _ part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?
  ) {
    self.callEventLoop.assertInEventLoop()
    self.logger.debug("buffering request part", metadata: [
      "request_part": "\(part.name)",
      "call_state": self.stateForLogging,
    ])
    self.writeBuffer.append(.init(request: part, promise: promise))
  }

  /// Writes any buffered request parts to the `Channel`.
  private func unbuffer() {
    self.callEventLoop.assertInEventLoop()

    guard let channel = self.channel else {
      return
    }

    // Save any flushing until we're done writing.
    var shouldFlush = false

    self.logger.debug("unbuffering request parts", metadata: [
      "request_parts": "\(self.writeBuffer.count)",
    ])

    // Why the double loop? A promise completed as a result of the flush may enqueue more writes,
    // or causes us to change state (i.e. we may have to close). If we didn't loop around then we
    // may miss more buffered writes.
    while self.state.isUnbuffering, !self.writeBuffer.isEmpty {
      // Pull out as many writes as possible.
      while let write = self.writeBuffer.popFirst() {
        self.logger.debug("unbuffering request part", metadata: [
          "request_part": "\(write.request.name)",
        ])

        if !shouldFlush {
          shouldFlush = self.shouldFlush(after: write.request)
        }

        self.writeToChannel(channel, part: write.request, promise: write.promise, flush: false)
      }

      // Okay, flush now.
      if shouldFlush {
        shouldFlush = false
        channel.flush()
      }
    }

    if self.writeBuffer.isEmpty {
      self.logger.debug("request buffer drained")
    } else {
      self.logger.notice("unbuffering aborted", metadata: ["call_state": self.stateForLogging])
    }

    // We're unbuffered. What now?
    switch self.state.unbuffered() {
    case .doNothing:
      ()
    case .succeedChannelPromise:
      self.channelPromise?.succeed(channel)
    }
  }

  /// Fails any promises that come with buffered writes with `error`.
  /// - Parameter error: The `Error` to fail promises with.
  private func failBufferedWrites(with error: Error) {
    self.logger.debug("failing buffered writes", metadata: ["call_state": self.stateForLogging])

    while let write = self.writeBuffer.popFirst() {
      write.promise?.fail(error)
    }
  }

  /// Write a request part to the `Channel`.
  /// - Parameters:
  ///   - channel: The `Channel` to write `part` to.
  ///   - part: The request part to write.
  ///   - promise: A promise to complete once the write has been completed.
  ///   - flush: Whether to flush the `Channel` after writing.
  private func writeToChannel(
    _ channel: Channel,
    part: GRPCClientRequestPart<Request>,
    promise: EventLoopPromise<Void>?,
    flush: Bool
  ) {
    switch part {
    case let .metadata(headers):
      let head = self.makeRequestHead(with: headers)
      channel.write(self.wrapOutboundOut(.head(head)), promise: promise)

    case let .message(request, metadata):
      do {
        let bytes = try self.serializer.serialize(request, allocator: channel.allocator)
        let message = _MessageContext<ByteBuffer>(bytes, compressed: metadata.compress)
        channel.write(self.wrapOutboundOut(.message(message)), promise: promise)
      } catch {
        self.handleError(error)
      }

    case .end:
      channel.write(self.wrapOutboundOut(.end), promise: promise)
    }

    if flush {
      channel.flush()
    }
  }

  /// Forward the response part to the interceptor pipeline.
  /// - Parameter part: The response part to forward.
  private func forwardToInterceptors(_ part: GRPCClientResponsePart<Response>) {
    self.callEventLoop.assertInEventLoop()
    self._pipeline?.receive(part)
  }

  /// Forward the error to the interceptor pipeline.
  /// - Parameter error: The error to forward.
  private func forwardErrorToInterceptors(_ error: Error) {
    self.callEventLoop.assertInEventLoop()
    self._pipeline?.errorCaught(error)
  }
}

// MARK: - Helpers

extension ClientTransport {
  /// Returns whether the `Channel` should be flushed after writing the given part to it.
  private func shouldFlush(after part: GRPCClientRequestPart<Request>) -> Bool {
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

extension GRPCClientRequestPart {
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

// A wrapper for connection errors: we need to be able to preserve the underlying error as
// well as extract a 'GRPCStatus' with code '.unavailable'.
internal struct ConnectionFailure: Error, GRPCStatusTransformable, CustomStringConvertible {
  /// The reason the connection failed.
  var reason: Error

  init(reason: Error) {
    self.reason = reason
  }

  var description: String {
    return String(describing: self.reason)
  }

  func makeGRPCStatus() -> GRPCStatus {
    return GRPCStatus(
      code: .unavailable,
      message: String(describing: self.reason),
      cause: self.reason
    )
  }
}
