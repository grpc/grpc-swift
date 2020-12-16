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

internal final class HTTP2ToRawGRPCServerCodec: ChannelDuplexHandler {
  typealias InboundIn = HTTP2Frame.FramePayload
  typealias InboundOut = GRPCServerRequestPart<ByteBuffer>

  typealias OutboundOut = HTTP2Frame.FramePayload
  typealias OutboundIn = GRPCServerResponsePart<ByteBuffer>

  private var logger: Logger
  private var state: HTTP2ToRawGRPCStateMachine
  private let errorDelegate: ServerErrorDelegate?

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

  /// Called when the pipeline has finished configuring.
  private func configured(context: ChannelHandlerContext) {
    self.act(on: self.state.pipelineConfigured(), with: context)
  }

  /// Act on an action returned from the state machine.
  private func act(
    on action: HTTP2ToRawGRPCStateMachine.Action,
    with context: ChannelHandlerContext
  ) {
    switch action {
    case .none:
      ()

    case let .configure(handler):
      context.channel.pipeline.addHandler(handler).whenSuccess {
        self.configured(context: context)
      }

    case let .errorCaught(error):
      context.fireErrorCaught(error)

    case let .forwardHeaders(metadata):
      context.fireChannelRead(self.wrapInboundOut(.metadata(metadata)))

    case let .forwardMessage(buffer):
      context.fireChannelRead(self.wrapInboundOut(.message(buffer)))

    case let .forwardMessageAndEnd(buffer):
      context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      context.fireChannelRead(self.wrapInboundOut(.end))

    case let .forwardHeadersThenReadNextMessage(metadata):
      context.fireChannelRead(self.wrapInboundOut(.metadata(metadata)))
      self.act(on: self.state.readNextRequest(), with: context)

    case let .forwardMessageThenReadNextMessage(buffer):
      context.fireChannelRead(self.wrapInboundOut(.message(buffer)))
      self.act(on: self.state.readNextRequest(), with: context)

    case .forwardEnd:
      context.fireChannelRead(self.wrapInboundOut(.end))

    case .readNextRequest:
      self.act(on: self.state.readNextRequest(), with: context)

    case let .write(part, promise, insertFlush):
      context.write(self.wrapOutboundOut(part), promise: promise)
      if insertFlush {
        context.flush()
      }

    case let .completePromise(promise, result):
      promise?.completeWith(result)
    }
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let payload = self.unwrapInboundIn(data)

    switch payload {
    case let .headers(payload):
      let action = self.state.receive(
        headers: payload.headers,
        eventLoop: context.eventLoop,
        errorDelegate: self.errorDelegate,
        remoteAddress: context.channel.remoteAddress,
        logger: self.logger
      )
      self.act(on: action, with: context)

    case let .data(payload):
      switch payload.data {
      case var .byteBuffer(buffer):
        let action = self.state.receive(buffer: &buffer, endStream: payload.endStream)
        self.act(on: action, with: context)

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
    let action: HTTP2ToRawGRPCStateMachine.Action

    switch responsePart {
    case let .metadata(headers):
      action = self.state.send(headers: headers, promise: promise)

    case let .message(buffer, metadata):
      action = self.state.send(
        buffer: buffer,
        allocator: context.channel.allocator,
        compress: metadata.compress,
        promise: promise
      )

    case let .end(status, trailers):
      action = self.state.send(status: status, trailers: trailers, promise: promise)
    }

    self.act(on: action, with: context)
  }
}
