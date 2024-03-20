/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

import GRPCCore
import NIOCore
import NIOHTTP2

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
final class GRPCClientStreamHandler: ChannelDuplexHandler {
  typealias InboundIn = HTTP2Frame.FramePayload
  typealias InboundOut = RPCRequestPart

  typealias OutboundIn = RPCRequestPart
  typealias OutboundOut = HTTP2Frame.FramePayload

  private var stateMachine: GRPCStreamStateMachine

  private var isReading = false
  private var flushPending = false

  init(
    methodDescriptor: MethodDescriptor,
    scheme: Scheme,
    outboundEncoding: CompressionAlgorithm,
    acceptedEncodings: [CompressionAlgorithm],
    maximumPayloadSize: Int,
    skipStateMachineAssertions: Bool = false
  ) {
      self.stateMachine = .init(
        configuration: .client(.init(
            methodDescriptor: methodDescriptor,
            scheme: scheme,
            outboundEncoding: outboundEncoding,
            acceptedEncodings: acceptedEncodings
        )),
        maximumPayloadSize: maximumPayloadSize,
        skipAssertions: skipStateMachineAssertions
      )
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    self.isReading = true
    let frame = self.unwrapInboundIn(data)
    switch frame {
    case .data(let frameData):
      let endStream = frameData.endStream
      switch frameData.data {
      case .byteBuffer(let buffer):
        do {
          try self.stateMachine.receive(message: buffer, endStream: endStream)
          switch self.stateMachine.nextInboundMessage() {
          case .awaitMoreMessages:
            ()
          case .receiveMessage(let message):
            context.fireChannelRead(self.wrapInboundOut(.message(message)))
          case .noMoreMessages:
            context.fireUserInboundEventTriggered(ChannelEvent.inputClosed)
          }
        } catch {
          context.fireErrorCaught(error)
        }
      case .fileRegion:
        preconditionFailure("Unexpected IOData.fileRegion")
      }

    case .headers(let headers):
      do {
        let action = try self.stateMachine.receive(
          metadata: headers.headers,
          endStream: headers.endStream
        )
        switch action {
        case .receivedMetadata(let metadata):
          context.fireChannelRead(self.wrapInboundOut(.metadata(metadata)))
        case .rejectRPC(let trailers):
          let response = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
          context.write(self.wrapOutboundOut(response), promise: nil)
          self.flushPending = true
        case .receivedStatusAndMetadata:
          throw RPCError(
            code: .internalError,
            message: "Server cannot get receivedStatusAndMetadata."
          )
        case .doNothing:
          throw RPCError(code: .internalError, message: "Server cannot receive doNothing.")
        }
      } catch {
        context.fireErrorCaught(error)
      }

    case .ping, .goAway, .priority, .rstStream, .settings, .pushPromise, .windowUpdate,
      .alternativeService, .origin:
      ()
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    self.isReading = false
    if self.flushPending {
      self.flushPending = false
      context.flush()
    }
    context.fireChannelReadComplete()
  }

  func handlerRemoved(context: ChannelHandlerContext) {
    self.stateMachine.tearDown()
  }
}

// - MARK: ChannelOutboundHandler

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServerStreamHandler {
  private func flushIfNeeded(_ context: ChannelHandlerContext) {
    if self.isReading {
      self.flushPending = true
    } else {
      context.flush()
    }
  }

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let frame = self.unwrapOutboundIn(data)
    switch frame {
    case .metadata(let metadata):
      do {
        let headers = try self.stateMachine.send(metadata: metadata)
        context.write(self.wrapOutboundOut(.headers(.init(headers: headers))), promise: nil)
        self.flushIfNeeded(context)
        // TODO: move the promise handling into the state machine
        promise?.succeed()
      } catch {
        context.fireErrorCaught(error)
        // TODO: move the promise handling into the state machine
        promise?.fail(error)
      }

    case .message(let message):
      do {
        try self.stateMachine.send(message: message, endStream: false)
        self.flushIfNeeded(context)
        // TODO: move the promise handling into the state machine
        promise?.succeed()
      } catch {
        context.fireErrorCaught(error)
        // TODO: move the promise handling into the state machine
        promise?.fail(error)
      }

    case .status(let status, let metadata):
      do {
        let headers = try self.stateMachine.send(status: status, metadata: metadata)
        let response = HTTP2Frame.FramePayload.headers(.init(headers: headers, endStream: true))
        context.write(self.wrapOutboundOut(response), promise: nil)
        self.flushIfNeeded(context)
        // TODO: move the promise handling into the state machine
        promise?.succeed()
      } catch {
        context.fireErrorCaught(error)
        // TODO: move the promise handling into the state machine
        promise?.fail(error)
      }
    }
  }

  func flush(context: ChannelHandlerContext) {
    do {
      switch try self.stateMachine.nextOutboundMessage() {
      case .noMoreMessages:
        // We shouldn't close the channel in this case, because we still have
        // to send back a status and trailers to properly end the RPC stream.
        ()
      case .awaitMoreMessages:
        ()
      case .sendMessage(let byteBuffer):
        context.writeAndFlush(
          self.wrapOutboundOut(.data(.init(data: .byteBuffer(byteBuffer)))),
          promise: nil
        )
      }
    } catch {
      context.fireErrorCaught(error)
    }
  }
}
