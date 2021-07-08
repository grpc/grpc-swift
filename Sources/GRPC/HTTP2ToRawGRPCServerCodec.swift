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

internal final class HTTP2ToRawGRPCServerCodec: ChannelInboundHandler, GRPCServerResponseWriter {
  typealias InboundIn = HTTP2Frame.FramePayload
  typealias OutboundOut = HTTP2Frame.FramePayload

  private var logger: Logger
  private var state: HTTP2ToRawGRPCStateMachine
  private let errorDelegate: ServerErrorDelegate?
  private var context: ChannelHandlerContext!

  private let servicesByName: [Substring: CallHandlerProvider]
  private let encoding: ServerMessageEncoding
  private let normalizeHeaders: Bool
  private let maxReceiveMessageLength: Int

  /// The configuration state of the handler.
  private var configurationState: Configuration = .notConfigured

  /// Whether we are currently reading data from the `Channel`. Should be set to `false` once a
  /// burst of reading has completed.
  private var isReading = false

  /// Indicates whether a flush event is pending. If a flush is received while `isReading` is `true`
  /// then it is held until the read completes in order to elide unnecessary flushes.
  private var flushPending = false

  private enum Configuration {
    case notConfigured
    case configured(GRPCServerHandlerProtocol)

    var isConfigured: Bool {
      switch self {
      case .configured:
        return true
      case .notConfigured:
        return false
      }
    }

    mutating func tearDown() -> GRPCServerHandlerProtocol? {
      switch self {
      case .notConfigured:
        return nil
      case let .configured(handler):
        self = .notConfigured
        return handler
      }
    }
  }

  init(
    servicesByName: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    errorDelegate: ServerErrorDelegate?,
    normalizeHeaders: Bool,
    maximumReceiveMessageLength: Int,
    logger: Logger
  ) {
    self.logger = logger
    self.errorDelegate = errorDelegate
    self.servicesByName = servicesByName
    self.encoding = encoding
    self.normalizeHeaders = normalizeHeaders
    self.maxReceiveMessageLength = maximumReceiveMessageLength
    self.state = HTTP2ToRawGRPCStateMachine()
  }

  internal func handlerAdded(context: ChannelHandlerContext) {
    self.context = context
  }

  internal func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
    self.configurationState = .notConfigured
  }

  internal func errorCaught(context: ChannelHandlerContext, error: Error) {
    switch self.configurationState {
    case .notConfigured:
      context.close(mode: .all, promise: nil)
    case let .configured(hander):
      hander.receiveError(error)
    }
  }

  internal func channelInactive(context: ChannelHandlerContext) {
    if let handler = self.configurationState.tearDown() {
      handler.finish()
    } else {
      context.fireChannelInactive()
    }
  }

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    self.isReading = true
    let payload = self.unwrapInboundIn(data)

    switch payload {
    case let .headers(payload):
      let receiveHeaders = self.state.receive(
        headers: payload.headers,
        eventLoop: context.eventLoop,
        errorDelegate: self.errorDelegate,
        remoteAddress: context.channel.remoteAddress,
        logger: self.logger,
        allocator: context.channel.allocator,
        responseWriter: self,
        closeFuture: context.channel.closeFuture,
        services: self.servicesByName,
        encoding: self.encoding,
        normalizeHeaders: self.normalizeHeaders
      )

      switch receiveHeaders {
      case let .configure(handler):
        assert(!self.configurationState.isConfigured)
        self.configurationState = .configured(handler)
        self.configured()

      case let .rejectRPC(trailers):
        assert(!self.configurationState.isConfigured)
        // We're not handling this request: write headers and end stream.
        let payload = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
        context.writeAndFlush(self.wrapOutboundOut(payload), promise: nil)
      }

    case let .data(payload):
      switch payload.data {
      case var .byteBuffer(buffer):
        let action = self.state.receive(buffer: &buffer, endStream: payload.endStream)
        switch action {
        case .tryReading:
          self.tryReadingMessage()

        case .finishHandler:
          let handler = self.configurationState.tearDown()
          handler?.finish()

        case .nothing:
          ()
        }

      case .fileRegion:
        preconditionFailure("Unexpected IOData.fileRegion")
      }

    // Ignored.
    case .alternativeService,
         .goAway,
         .origin,
         .ping,
         .priority,
         .pushPromise,
         .rstStream,
         .settings,
         .windowUpdate:
      ()
    }
  }

  internal func channelReadComplete(context: ChannelHandlerContext) {
    self.isReading = false

    if self.flushPending {
      self.flushPending = false
      context.flush()
    }

    context.fireChannelReadComplete()
  }

  /// Called when the pipeline has finished configuring.
  private func configured() {
    switch self.state.pipelineConfigured() {
    case let .forwardHeaders(headers):
      switch self.configurationState {
      case .notConfigured:
        preconditionFailure()
      case let .configured(handler):
        handler.receiveMetadata(headers)
      }

    case let .forwardHeadersAndRead(headers):
      switch self.configurationState {
      case .notConfigured:
        preconditionFailure()
      case let .configured(handler):
        handler.receiveMetadata(headers)
      }
      self.tryReadingMessage()
    }
  }

  /// Try to read a request message from the buffer.
  private func tryReadingMessage() {
    // This while loop exists to break the recursion in `.forwardMessageThenReadNextMessage`.
    // Almost all cases return directly out of the loop.
    while true {
      let action = self.state.readNextRequest(
        maxLength: self.maxReceiveMessageLength
      )
      switch action {
      case .none:
        return

      case let .forwardMessage(buffer):
        switch self.configurationState {
        case .notConfigured:
          preconditionFailure()
        case let .configured(handler):
          handler.receiveMessage(buffer)
        }

        return

      case let .forwardMessageThenReadNextMessage(buffer):
        switch self.configurationState {
        case .notConfigured:
          preconditionFailure()
        case let .configured(handler):
          handler.receiveMessage(buffer)
        }

        continue

      case .forwardEnd:
        switch self.configurationState {
        case .notConfigured:
          preconditionFailure()
        case let .configured(handler):
          handler.receiveEnd()
        }

        return

      case let .errorCaught(error):
        switch self.configurationState {
        case .notConfigured:
          preconditionFailure()
        case let .configured(handler):
          handler.receiveError(error)
        }

        return
      }
    }
  }

  internal func sendMetadata(
    _ headers: HPACKHeaders,
    flush: Bool,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.state.send(headers: headers) {
    case let .success(headers):
      let payload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
      self.context.write(self.wrapOutboundOut(payload), promise: promise)
      if flush {
        self.markFlushPoint()
      }

    case let .failure(error):
      promise?.fail(error)
    }
  }

  internal func sendMessage(
    _ buffer: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    let writeBuffer = self.state.send(
      buffer: buffer,
      allocator: self.context.channel.allocator,
      compress: metadata.compress
    )

    switch writeBuffer {
    case let .success(buffer):
      let payload = HTTP2Frame.FramePayload.data(.init(data: .byteBuffer(buffer)))
      self.context.write(self.wrapOutboundOut(payload), promise: promise)
      if metadata.flush {
        self.markFlushPoint()
      }

    case let .failure(error):
      promise?.fail(error)
    }
  }

  internal func sendEnd(
    status: GRPCStatus,
    trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.state.send(status: status, trailers: trailers) {
    case let .sendTrailers(trailers):
      self.sendTrailers(trailers, promise: promise)

    case let .sendTrailersAndFinish(trailers):
      self.sendTrailers(trailers, promise: promise)

      // 'finish' the handler.
      let handler = self.configurationState.tearDown()
      handler?.finish()

    case let .failure(error):
      promise?.fail(error)
    }
  }

  private func sendTrailers(_ trailers: HPACKHeaders, promise: EventLoopPromise<Void>?) {
    // Always end stream for status and trailers.
    let payload = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
    self.context.write(self.wrapOutboundOut(payload), promise: promise)
    // We'll always flush on end.
    self.markFlushPoint()
  }

  /// Mark a flush as pending - to be emitted once the read completes - if we're currently reading,
  /// or emit a flush now if we are not.
  private func markFlushPoint() {
    if self.isReading {
      self.flushPending = true
    } else {
      self.flushPending = false
      self.context.flush()
    }
  }
}
