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

internal final class HTTP2ToRawGRPCServerCodec: ChannelDuplexHandler, GRPCServerResponseWriter {
  typealias InboundIn = HTTP2Frame.FramePayload
  typealias InboundOut = GRPCServerRequestPart<ByteBuffer>

  typealias OutboundOut = HTTP2Frame.FramePayload
  typealias OutboundIn = GRPCServerResponsePart<ByteBuffer>

  private var logger: Logger
  private var state: HTTP2ToRawGRPCStateMachine
  private let errorDelegate: ServerErrorDelegate?
  private var context: ChannelHandlerContext!

  /// The mode we're operating in.
  private var mode: Mode = .notConfigured

  /// Whether we are currently reading data from the `Channel`. Should be set to `false` once a
  /// burst of reading has completed.
  private var isReading = false

  /// Indicates whether a flush event is pending. If a flush is received while `isReading` is `true`
  /// then it is held until the read completes in order to elide unnecessary flushes.
  private var flushPending = false

  private enum Mode {
    case notConfigured
    case legacy
    case handler(GRPCServerHandlerProtocol)
  }

  init(
    servicesByName: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    errorDelegate: ServerErrorDelegate?,
    normalizeHeaders: Bool,
    logger: Logger
  ) {
    self.logger = logger
    self.errorDelegate = errorDelegate
    self.state = HTTP2ToRawGRPCStateMachine(
      services: servicesByName,
      encoding: encoding,
      normalizeHeaders: normalizeHeaders
    )
  }

  internal func handlerAdded(context: ChannelHandlerContext) {
    self.context = context
  }

  internal func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
  }

  internal func errorCaught(context: ChannelHandlerContext, error: Error) {
    switch self.mode {
    case .notConfigured:
      context.close(mode: .all, promise: nil)
    case .legacy:
      context.fireErrorCaught(error)
    case let .handler(hander):
      hander.receiveError(error)
    }
  }

  internal func channelInactive(context: ChannelHandlerContext) {
    switch self.mode {
    case .notConfigured, .legacy:
      context.fireChannelInactive()
    case let .handler(handler):
      handler.finish()
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
        responseWriter: self
      )

      switch receiveHeaders {
      case let .configureLegacy(handler):
        self.mode = .legacy
        context.channel.pipeline.addHandler(handler).whenSuccess {
          self.configured()
        }

      case let .configure(handler):
        self.mode = .handler(handler)
        self.configured()

      case let .rejectRPC(trailers):
        // We're not handling this request: write headers and end stream.
        let payload = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
        context.writeAndFlush(self.wrapOutboundOut(payload), promise: nil)
      }

    case let .data(payload):
      switch payload.data {
      case var .byteBuffer(buffer):
        let tryToRead = self.state.receive(buffer: &buffer, endStream: payload.endStream)
        if tryToRead {
          self.tryReadingMessage()
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

  internal func write(
    context: ChannelHandlerContext,
    data: NIOAny,
    promise: EventLoopPromise<Void>?
  ) {
    let responsePart = self.unwrapOutboundIn(data)

    switch responsePart {
    case let .metadata(headers):
      // We're in 'write' so we're using the old type of RPC handler which emits its own flushes,
      // no need to emit an extra one.
      self.sendMetadata(headers, flush: false, promise: promise)

    case let .message(buffer, metadata):
      self.sendMessage(buffer, metadata: metadata, promise: promise)

    case let .end(status, trailers):
      self.sendEnd(status: status, trailers: trailers, promise: promise)
    }
  }

  internal func flush(context: ChannelHandlerContext) {
    self.markFlushPoint()
  }

  /// Called when the pipeline has finished configuring.
  private func configured() {
    switch self.state.pipelineConfigured() {
    case let .forwardHeaders(headers):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.metadata(headers)))
      case let .handler(handler):
        handler.receiveMetadata(headers)
      }

    case let .forwardHeadersAndRead(headers):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.metadata(headers)))
      case let .handler(handler):
        handler.receiveMetadata(headers)
      }
      self.tryReadingMessage()
    }
  }

  /// Try to read a request message from the buffer.
  private func tryReadingMessage() {
    let action = self.state.readNextRequest()
    switch action {
    case .none:
      ()

    case let .forwardMessage(buffer):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      case let .handler(handler):
        handler.receiveMessage(buffer)
      }

    case let .forwardMessageAndEnd(buffer):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
        self.context.fireChannelRead(self.wrapInboundOut(.end))
      case let .handler(handler):
        handler.receiveMessage(buffer)
        handler.receiveEnd()
      }

    case let .forwardMessageThenReadNextMessage(buffer):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      case let .handler(handler):
        handler.receiveMessage(buffer)
      }
      self.tryReadingMessage()

    case .forwardEnd:
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireChannelRead(self.wrapInboundOut(.end))
      case let .handler(handler):
        handler.receiveEnd()
      }

    case let .errorCaught(error):
      switch self.mode {
      case .notConfigured:
        preconditionFailure()
      case .legacy:
        self.context.fireErrorCaught(error)
      case let .handler(handler):
        handler.receiveError(error)
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
    case let .success(trailers):
      // Always end stream for status and trailers.
      let payload = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
      self.context.write(self.wrapOutboundOut(payload), promise: promise)
      // We'll always flush on end.
      self.markFlushPoint()

    case let .failure(error):
      promise?.fail(error)
    }
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
