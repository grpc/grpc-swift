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

  func handlerAdded(context: ChannelHandlerContext) {
    self.context = context
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.context = nil
  }

  /// Called when the pipeline has finished configuring.
  private func configured() {
    switch self.state.pipelineConfigured() {
    case let .forwardHeaders(headers):
      self.context.fireChannelRead(self.wrapInboundOut(.metadata(headers)))

    case let .forwardHeadersAndRead(headers):
      self.context.fireChannelRead(self.wrapInboundOut(.metadata(headers)))
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
      self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))

    case let .forwardMessageAndEnd(buffer):
      self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      self.context.fireChannelRead(self.wrapInboundOut(.end))

    case let .forwardMessageThenReadNextMessage(buffer):
      self.context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      self.tryReadingMessage()

    case .forwardEnd:
      self.context.fireChannelRead(self.wrapInboundOut(.end))

    case let .errorCaught(error):
      self.context.fireErrorCaught(error)
    }
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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
      case let .configurePipeline(handler):
        context.channel.pipeline.addHandler(handler).whenSuccess {
          self.configured()
        }

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

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)

    switch responsePart {
    case let .metadata(headers):
      switch self.state.send(headers: headers) {
      case let .success(headers):
        let payload = HTTP2Frame.FramePayload.headers(.init(headers: headers))
        context.write(self.wrapOutboundOut(payload), promise: promise)

      case let .failure(error):
        promise?.fail(error)
      }

    case let .message(buffer, metadata):
      let writeBuffer = self.state.send(
        buffer: buffer,
        allocator: context.channel.allocator,
        compress: metadata.compress
      )

      switch writeBuffer {
      case let .success(buffer):
        let payload = HTTP2Frame.FramePayload.data(.init(data: .byteBuffer(buffer)))
        context.write(self.wrapOutboundOut(payload), promise: promise)

      case let .failure(error):
        promise?.fail(error)
      }

    case let .end(status, trailers):
      switch self.state.send(status: status, trailers: trailers) {
      case let .success(trailers):
        // Always end stream for status and trailers.
        let payload = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
        context.write(self.wrapOutboundOut(payload), promise: promise)

      case let .failure(error):
        promise?.fail(error)
      }
    }
  }

  internal func sendMetadata(
    _ metadata: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    fatalError("TODO: not used yet")
  }

  internal func sendMessage(
    _ bytes: ByteBuffer,
    metadata: MessageMetadata,
    promise: EventLoopPromise<Void>?
  ) {
    fatalError("TODO: not used yet")
  }

  internal func sendEnd(
    status: GRPCStatus,
    trailers: HPACKHeaders,
    promise: EventLoopPromise<Void>?
  ) {
    fatalError("TODO: not used yet")
  }
}
