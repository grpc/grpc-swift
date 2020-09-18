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

/// This class provides much of the boilerplate for the four types of gRPC call objects returned to
/// framework users. It is the glue between a call object and the underlying transport (typically a
/// NIO Channel).
///
/// Typically, each call will be configured on an HTTP/2 stream channel. The stream channel will
/// will be configured as such:
///
/// ```
///                           ┌────────────────────────────────────┐
///                           │ ChannelTransport<Request,Response> │
///                           └─────▲───────────────────────┬──────┘
///                                 │                       │
/// --------------------------------│-----------------------│------------------------------
/// HTTP2StreamChannel              │                       │
///                    ┌────────────┴──────────┐            │
///                    │ GRPCClientCallHandler │            │
///                    └────────────▲──────────┘            │
/// GRPCClientResponsePart<Response>│                       │GRPCClientRequestPart<Request>
///                               ┌─┴───────────────────────▼─┐
///                               │ GRPCClientChannelHandler  │
///                               └─▲───────────────────────┬─┘
///                       HTTP2Frame│                       │HTTP2Frame
///                                 |                       |
/// ```
///
/// Note: the "main" pipeline provided by the channel in `ClientConnection`.
internal class ChannelTransport<Request, Response> {
  internal typealias RequestPart = _GRPCClientRequestPart<Request>
  internal typealias ResponsePart = _GRPCClientResponsePart<Response>

  /// The `EventLoop` this call is running on.
  internal let eventLoop: EventLoop

  /// A logger.
  private let logger: Logger

  /// The current state of the call.
  private var state: State

  /// A scheduled timeout for the call.
  private var scheduledTimeout: Scheduled<Void>?

  // Note: initial capacity is 4 because it's a power of 2 and most calls are unary so will
  // have 3 parts.
  /// A buffer to store requests in before the channel has become active.
  private var requestBuffer = MarkedCircularBuffer<BufferedRequest>(initialCapacity: 4)

  /// A request that we'll deal with at a later point in time.
  private struct BufferedRequest {
    /// The request to write.
    var message: _GRPCClientRequestPart<Request>

    /// Any promise associated with the request.
    var promise: EventLoopPromise<Void>?
  }

  /// An error delegate provided by the user.
  private var errorDelegate: ClientErrorDelegate?

  /// A container for response part promises for the call.
  internal var responseContainer: ResponsePartContainer<Response>

  /// A stopwatch for timing the RPC.
  private var stopwatch: Stopwatch?

  enum State {
    // Waiting for a stream to become active.
    //
    // Valid transitions:
    // - active
    // - closed
    case buffering(EventLoopFuture<Channel>)

    // We have a channel, we're doing the RPC, there may be a timeout.
    //
    // Valid transitions:
    // - closed
    case active(Channel)

    // We're closed; the RPC is done for one reason or another. This is terminal.
    case closed
  }

  private init(
    eventLoop: EventLoop,
    state: State,
    responseContainer: ResponsePartContainer<Response>,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) {
    self.eventLoop = eventLoop
    self.state = state
    self.responseContainer = responseContainer
    self.errorDelegate = errorDelegate
    self.logger = logger

    self.startTimer()
  }

  internal convenience init(
    eventLoop: EventLoop,
    responseContainer: ResponsePartContainer<Response>,
    timeLimit: TimeLimit,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger,
    channelProvider: (ChannelTransport<Request, Response>, EventLoopPromise<Channel>) -> Void
  ) {
    let channelPromise = eventLoop.makePromise(of: Channel.self)

    self.init(
      eventLoop: eventLoop,
      state: .buffering(channelPromise.futureResult),
      responseContainer: responseContainer,
      errorDelegate: errorDelegate,
      logger: logger
    )

    // If the channel creation fails we need to error the call. Note that we receive an
    // 'activation' from the channel instead of relying on the success of the future.
    channelPromise.futureResult.whenFailure { error in
      self.handleError(error, promise: nil)
    }

    // Schedule the timeout.
    self.setUpTimeLimit(timeLimit)

    // Now attempt to make the channel.
    channelProvider(self, channelPromise)
  }

  internal convenience init<Serializer: MessageSerializer, Deserializer: MessageDeserializer>(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    serializer: Serializer,
    deserializer: Deserializer,
    responseContainer: ResponsePartContainer<Response>,
    callType: GRPCCallType,
    timeLimit: TimeLimit,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) where Serializer.Input == Request, Deserializer.Output == Response {
    self.init(
      eventLoop: multiplexer.eventLoop,
      responseContainer: responseContainer,
      timeLimit: timeLimit,
      errorDelegate: errorDelegate,
      logger: logger
    ) { call, streamPromise in
      multiplexer.whenComplete { result in
        switch result {
        case let .success(mux):
          mux.createStreamChannel(promise: streamPromise) { stream in
            stream.pipeline.addHandlers([
              _GRPCClientChannelHandler(callType: callType, logger: logger),
              GRPCClientCodecHandler(serializer: serializer, deserializer: deserializer),
              GRPCClientCallHandler(call: call),
            ])
          }

        case let .failure(error):
          streamPromise.fail(error)
        }
      }
    }
  }

  internal convenience init(
    fakeResponse: _FakeResponseStream<Request, Response>,
    responseContainer: ResponsePartContainer<Response>,
    timeLimit: TimeLimit,
    logger: Logger
  ) {
    self.init(
      eventLoop: fakeResponse.channel.eventLoop,
      responseContainer: responseContainer,
      timeLimit: timeLimit,
      errorDelegate: nil,
      logger: logger
    ) { call, streamPromise in
      fakeResponse.channel.pipeline.addHandler(GRPCClientCallHandler(call: call)).map {
        fakeResponse.channel
      }.cascade(to: streamPromise)
    }
  }

  /// Makes a transport whose channel promise is failed immediately.
  internal static func makeTransportForMissingFakeResponse(
    eventLoop: EventLoop,
    responseContainer: ResponsePartContainer<Response>,
    logger: Logger
  ) -> ChannelTransport<Request, Response> {
    return .init(
      eventLoop: eventLoop,
      responseContainer: responseContainer,
      timeLimit: .none,
      errorDelegate: nil,
      logger: logger
    ) { _, promise in
      let error = GRPCStatus(
        code: .unavailable,
        message: "No fake response was registered before starting an RPC."
      )
      promise.fail(error)
    }
  }
}

// MARK: - Call API (i.e. called from {Unary,ClientStreaming,...}Call)

extension ChannelTransport: ClientCallOutbound {
  /// Send a request part.
  ///
  /// Does not have to be called from the event loop.
  internal func sendRequest(_ part: RequestPart, promise: EventLoopPromise<Void>?) {
    if self.eventLoop.inEventLoop {
      self.writePart(part, flush: true, promise: promise)
    } else {
      self.eventLoop.execute {
        self.writePart(part, flush: true, promise: promise)
      }
    }
  }

  /// Send multiple request parts.
  ///
  /// Does not have to be called from the event loop.
  internal func sendRequests<S>(
    _ parts: S,
    promise: EventLoopPromise<Void>?
  ) where S: Sequence, S.Element == RequestPart {
    if self.eventLoop.inEventLoop {
      self._sendRequests(parts, promise: promise)
    } else {
      self.eventLoop.execute {
        self._sendRequests(parts, promise: promise)
      }
    }
  }

  /// Request that the RPC is cancelled.
  ///
  /// Does not have to be called from the event loop.
  internal func cancel(promise: EventLoopPromise<Void>?) {
    self.logger.info("rpc cancellation requested", source: "GRPC")

    if self.eventLoop.inEventLoop {
      self.handleError(GRPCError.RPCCancelledByClient().captureContext(), promise: promise)
    } else {
      self.eventLoop.execute {
        self.handleError(GRPCError.RPCCancelledByClient().captureContext(), promise: promise)
      }
    }
  }

  /// Returns the `Channel` for the HTTP/2 stream that this RPC is using.
  internal func streamChannel() -> EventLoopFuture<Channel> {
    if self.eventLoop.inEventLoop {
      return self.getStreamChannel()
    } else {
      return self.eventLoop.flatSubmit {
        self.getStreamChannel()
      }
    }
  }
}

extension ChannelTransport {
  /// Return a future for the stream channel.
  ///
  /// Must be called from the event loop.
  private func getStreamChannel() -> EventLoopFuture<Channel> {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case let .buffering(future):
      return future

    case let .active(channel):
      return self.eventLoop.makeSucceededFuture(channel)

    case .closed:
      return self.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel)
    }
  }

  /// Send many requests.
  ///
  /// Must be called from the event loop.
  private func _sendRequests<S>(
    _ parts: S,
    promise: EventLoopPromise<Void>?
  ) where S: Sequence, S.Element == RequestPart {
    self.eventLoop.preconditionInEventLoop()

    // We have a promise: create one for each request part and cascade the overall result to it.
    // If we're flushing we'll do it at the end.
    if let promise = promise {
      let loop = promise.futureResult.eventLoop

      let futures: [EventLoopFuture<Void>] = parts.map { part in
        let partPromise = loop.makePromise(of: Void.self)
        self.writePart(part, flush: false, promise: partPromise)
        return partPromise.futureResult
      }

      // Cascade the futures to the provided promise.
      EventLoopFuture.andAllSucceed(futures, on: loop).cascade(to: promise)
    } else {
      for part in parts {
        self.writePart(part, flush: false, promise: nil)
      }
    }

    // Now flush.
    self.flush()
  }

  /// Buffer or send a flush.
  ///
  /// Must be called from the event loop.
  private func flush() {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .buffering:
      self.requestBuffer.mark()

    case let .active(stream):
      stream.flush()

    case .closed:
      ()
    }
  }

  /// Write a request part.
  ///
  /// Must be called from the event loop.
  ///
  /// - Parameters:
  ///   - part: The part to write.
  ///   - flush: Whether we should flush the channel after this write.
  ///   - promise: A promise to fulfill when the part has been written.
  private func writePart(_ part: RequestPart, flush: Bool, promise: EventLoopPromise<Void>?) {
    self.eventLoop.assertInEventLoop()

    switch self.state {
    // We're buffering, so buffer the message.
    case .buffering:
      self.logger.debug("buffering request part", metadata: [
        "request_part": "\(part.name)",
        "call_state": "\(self.describeCallState())",
      ], source: "GRPC")
      self.requestBuffer.append(BufferedRequest(message: part, promise: promise))
      if flush {
        self.requestBuffer.mark()
      }

    // We have an active stream, just pass the write and promise through.
    case let .active(stream):
      self.logger.debug(
        "writing request part",
        metadata: ["request_part": "\(part.name)"],
        source: "GRPC"
      )
      stream.write(part, promise: promise)
      if flush {
        stream.flush()
      }

    // We're closed: drop the request.
    case .closed:
      self.logger.debug("dropping request part", metadata: [
        "request_part": "\(part.name)",
        "call_state": "\(self.describeCallState())",
      ], source: "GRPC")
      promise?.fail(ChannelError.ioOnClosedChannel)
    }
  }

  /// The scheduled timeout triggered: timeout the RPC if it's not yet finished.
  ///
  /// Must be called from the event loop.
  private func timedOut(after timeLimit: TimeLimit) {
    self.eventLoop.preconditionInEventLoop()

    let error = GRPCError.RPCTimedOut(timeLimit).captureContext()
    self.handleError(error, promise: nil)
  }

  /// Handle an error and optionally fail the provided promise with the error.
  ///
  /// Must be called from the event loop.
  private func handleError(_ error: Error, promise: EventLoopPromise<Void>?) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    // We only care about errors if we're not shutdown yet.
    case .buffering, .active:
      // Add our current state to the logger we provide to the callback.
      var loggerWithState = self.logger
      loggerWithState[metadataKey: "call_state"] = "\(self.describeCallState())"
      let errorStatus: GRPCStatus
      let errorWithoutContext: Error

      if let errorWithContext = error as? GRPCError.WithContext {
        errorStatus = errorWithContext.error.makeGRPCStatus()
        errorWithoutContext = errorWithContext.error
        self.errorDelegate?.didCatchError(
          errorWithContext.error,
          logger: loggerWithState,
          file: errorWithContext.file,
          line: errorWithContext.line
        )
      } else if let transformable = error as? GRPCStatusTransformable {
        errorStatus = transformable.makeGRPCStatus()
        errorWithoutContext = error
        self.errorDelegate?.didCatchErrorWithoutContext(error, logger: loggerWithState)
      } else {
        errorStatus = .processingError
        errorWithoutContext = error
        self.errorDelegate?.didCatchErrorWithoutContext(error, logger: loggerWithState)
      }

      // Update our state: we're closing.
      self.close(error: errorWithoutContext, status: errorStatus)
      promise?.fail(errorStatus)

    case .closed:
      promise?.fail(ChannelError.alreadyClosed)
    }
  }

  /// Close the call, if it's not yet closed with the given status.
  ///
  /// Must be called from the event loop.
  private func close(error: Error, status: GRPCStatus) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case let .buffering(streamFuture):
      // We're closed now.
      self.state = .closed
      self.stopTimer(status: status)

      // We're done; cancel the timeout.
      self.scheduledTimeout?.cancel()
      self.scheduledTimeout = nil

      // Fail any outstanding promises.
      self.responseContainer.fail(with: error, status: status)

      // Fail any buffered writes.
      while !self.requestBuffer.isEmpty {
        let write = self.requestBuffer.removeFirst()
        write.promise?.fail(status)
      }

      // Close the channel, if it comes up.
      streamFuture.whenSuccess {
        $0.close(mode: .all, promise: nil)
      }

    case let .active(channel):
      // We're closed now.
      self.state = .closed
      self.stopTimer(status: status)

      // We're done; cancel the timeout.
      self.scheduledTimeout?.cancel()
      self.scheduledTimeout = nil

      // Fail any outstanding promises.
      self.responseContainer.fail(with: error, status: status)

      // Close the channel.
      channel.close(mode: .all, promise: nil)

    case .closed:
      ()
    }
  }
}

// MARK: - Channel Inbound

extension ChannelTransport: ClientCallInbound {
  /// Receive an error from the Channel.
  ///
  /// Must be called on the event loop.
  internal func receiveError(_ error: Error) {
    self.eventLoop.preconditionInEventLoop()
    self.handleError(error, promise: nil)
  }

  /// Receive a response part from the Channel.
  ///
  /// Must be called on the event loop.
  func receiveResponse(_ part: _GRPCClientResponsePart<Response>) {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .buffering:
      preconditionFailure("Received response part in 'buffering' state")

    case .active:
      self.logger.debug(
        "received response part",
        metadata: ["response_part": "\(part.name)"],
        source: "GRPC"
      )

      switch part {
      case let .initialMetadata(metadata):
        self.responseContainer.lazyInitialMetadataPromise.completeWith(.success(metadata))

      case let .message(messageContext):
        switch self.responseContainer.responseHandler {
        case let .unary(responsePromise):
          responsePromise.succeed(messageContext.message)
        case let .stream(handler):
          handler(messageContext.message)
        }

      case let .trailingMetadata(metadata):
        self.responseContainer.lazyTrailingMetadataPromise.succeed(metadata)

      case let .status(status):
        // We're closed now.
        self.state = .closed
        self.stopTimer(status: status)

        // We're done; cancel the timeout.
        self.scheduledTimeout?.cancel()
        self.scheduledTimeout = nil

        // We're not really failing the status here; in some cases the server may fast fail, in which
        // case we'll only see trailing metadata and status: we should fail the initial metadata and
        // response in that case.
        self.responseContainer.fail(with: status, status: status)
      }

    case .closed:
      self.logger.debug("dropping response part", metadata: [
        "response_part": "\(part.name)",
        "call_state": "\(self.describeCallState())",
      ], source: "GRPC")
    }
  }

  /// The underlying channel become active and can start accepting writes.
  ///
  /// Must be called on the event loop.
  internal func activate(stream: Channel) {
    self.eventLoop.preconditionInEventLoop()
    self.logger.debug("activated stream channel", source: "GRPC")

    // The channel has become active: what now?
    switch self.state {
    case .buffering:
      while !self.requestBuffer.isEmpty {
        // Are we marked?
        let hadMark = self.requestBuffer.hasMark
        let request = self.requestBuffer.removeFirst()
        // We became unmarked: we need to flush.
        let shouldFlush = hadMark && !self.requestBuffer.hasMark

        self.logger.debug(
          "unbuffering request part",
          metadata: ["request_part": "\(request.message.name)"],
          source: "GRPC"
        )
        stream.write(request.message, promise: request.promise)
        if shouldFlush {
          stream.flush()
        }
      }

      self.logger.debug("request buffer drained", source: "GRPC")
      self.state = .active(stream)

    case .active:
      preconditionFailure("Invalid state: stream is already active")

    case .closed:
      // The channel became active but we're already closed: we must've timed out waiting for the
      // channel to activate so close the channel now.
      stream.close(mode: .all, promise: nil)
    }
  }
}

// MARK: Private Helpers

extension ChannelTransport {
  private func describeCallState() -> String {
    self.eventLoop.preconditionInEventLoop()

    switch self.state {
    case .buffering:
      return "waiting for connection; \(self.requestBuffer.count) request part(s) buffered"
    case .active:
      return "active"
    case .closed:
      return "closed"
    }
  }

  private func startTimer() {
    assert(self.stopwatch == nil)
    self.stopwatch = Stopwatch()
    self.logger.debug("starting rpc", source: "GRPC")
  }

  private func stopTimer(status: GRPCStatus) {
    self.eventLoop.preconditionInEventLoop()

    if let stopwatch = self.stopwatch {
      let millis = stopwatch.elapsedMillis()
      self.logger.debug("rpc call finished", metadata: [
        "duration_ms": "\(millis)",
        "status_code": "\(status.code.rawValue)",
        "status_message": "\(status.message ?? "nil")",
      ], source: "GRPC")
      self.stopwatch = nil
    }
  }

  /// Sets a time limit for the RPC.
  private func setUpTimeLimit(_ timeLimit: TimeLimit) {
    let deadline = timeLimit.makeDeadline()

    guard deadline != .distantFuture else {
      // This is too distant to worry about.
      return
    }

    let timedOutTask = {
      self.timedOut(after: timeLimit)
    }

    // 'scheduledTimeout' must only be accessed from the event loop.
    if self.eventLoop.inEventLoop {
      self.scheduledTimeout = self.eventLoop.scheduleTask(deadline: deadline, timedOutTask)
    } else {
      self.eventLoop.execute {
        self.scheduledTimeout = self.eventLoop.scheduleTask(deadline: deadline, timedOutTask)
      }
    }
  }
}

extension _GRPCClientRequestPart {
  fileprivate var name: String {
    switch self {
    case .head:
      return "head"
    case .message:
      return "message"
    case .end:
      return "end"
    }
  }
}

extension _GRPCClientResponsePart {
  fileprivate var name: String {
    switch self {
    case .initialMetadata:
      return "initial metadata"
    case .message:
      return "message"
    case .trailingMetadata:
      return "trailing metadata"
    case .status:
      return "status"
    }
  }
}
