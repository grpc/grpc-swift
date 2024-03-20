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
final class GRPCServerStreamHandler: ChannelDuplexHandler {
  typealias InboundIn = HTTP2Frame.FramePayload
  typealias InboundOut = RPCRequestPart

  typealias OutboundIn = RPCResponsePart
  typealias OutboundOut = HTTP2Frame.FramePayload

  private var stateMachine: GRPCStreamStateMachine

  private var isReading = false
  private var flushPending = false

  // We buffer the final status + trailers to avoid reordering issues (i.e.,
  // if there are messages still not written into the channel because flush has
  // not been called, but the server sends back trailers).
  private var pendingTrailers: HTTP2Frame.FramePayload?

  init(
    scheme: Scheme,
    acceptedEncodings: [CompressionAlgorithm],
    maximumPayloadSize: Int,
    skipStateMachineAssertions: Bool = false
  ) {
    self.stateMachine = .init(
      configuration: .server(.init(scheme: scheme, acceptedEncodings: acceptedEncodings)),
      maximumPayloadSize: maximumPayloadSize,
      skipAssertions: skipStateMachineAssertions
    )
  }
}

// - MARK: ChannelInboundHandler

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCServerStreamHandler {
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

          var nextInboundMessage = self.stateMachine.nextInboundMessage()
          while case .receiveMessage(let message) = nextInboundMessage {
            context.fireChannelRead(self.wrapInboundOut(.message(message)))
            nextInboundMessage = self.stateMachine.nextInboundMessage()
          }

          switch nextInboundMessage {
          case .awaitMoreMessages:
            ()
          case .receiveMessage:
            preconditionFailure("This isn't possible: we'd still be inside the while loop.")
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
  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let frame = self.unwrapOutboundIn(data)
    switch frame {
    case .metadata(let metadata):
      do {
        let headers = try self.stateMachine.send(metadata: metadata)
        context.write(self.wrapOutboundOut(.headers(.init(headers: headers))), promise: nil)
        self.flushPending = true
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
        self.pendingTrailers = response
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
      if self.isReading {
        // We don't want to flush yet if we're still in a read loop.
        return
      }

      var nextOutboundMessage = try self.stateMachine.nextOutboundMessage()
      while case .sendMessage(let byteBuffer) = nextOutboundMessage {
        context.write(
          self.wrapOutboundOut(.data(.init(data: .byteBuffer(byteBuffer)))),
          promise: nil
        )
        self.flushPending = true
        nextOutboundMessage = try self.stateMachine.nextOutboundMessage()
      }

      switch nextOutboundMessage {
      case .noMoreMessages:
        if let pendingTrailers = self.pendingTrailers {
          context.write(self.wrapOutboundOut(pendingTrailers), promise: nil)
          self.flushPending = true
          self.pendingTrailers = nil
        }
      case .awaitMoreMessages:
        ()
      case .sendMessage:
        preconditionFailure("This isn't possible: we'd still be inside the while loop.")
      }

      if self.flushPending {
        context.flush()
        self.flushPending = false
      }
    } catch {
      context.fireErrorCaught(error)
    }
  }
}
