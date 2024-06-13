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
final class GRPCServerStreamHandler: ChannelDuplexHandler, RemovableChannelHandler {
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
  private var pendingTrailers:
    (trailers: HTTP2Frame.FramePayload, promise: EventLoopPromise<Void>?)?

  private let methodDescriptorPromise: EventLoopPromise<MethodDescriptor>

  init(
    scheme: GRPCStreamStateMachineConfiguration.Scheme,
    acceptedEncodings: CompressionAlgorithmSet,
    maximumPayloadSize: Int,
    methodDescriptorPromise: EventLoopPromise<MethodDescriptor>,
    skipStateMachineAssertions: Bool = false
  ) {
    self.stateMachine = .init(
      configuration: .server(.init(scheme: scheme, acceptedEncodings: acceptedEncodings)),
      maximumPayloadSize: maximumPayloadSize,
      skipAssertions: skipStateMachineAssertions
    )
    self.methodDescriptorPromise = methodDescriptorPromise
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
          switch try self.stateMachine.receive(buffer: buffer, endStream: endStream) {
          case .endRPCAndForwardErrorStatus:
            preconditionFailure(
              "OnBufferReceivedAction.endRPCAndForwardErrorStatus should never be returned for the server."
            )
          case .readInbound:
            loop: while true {
              switch self.stateMachine.nextInboundMessage() {
              case .receiveMessage(let message):
                context.fireChannelRead(self.wrapInboundOut(.message(message)))
              case .awaitMoreMessages:
                break loop
              case .noMoreMessages:
                context.fireUserInboundEventTriggered(ChannelEvent.inputClosed)
                break loop
              }
            }
          case .doNothing:
            ()
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
          headers: headers.headers,
          endStream: headers.endStream
        )
        switch action {
        case .receivedMetadata(let metadata, let methodDescriptor):
          if let methodDescriptor = methodDescriptor {
            self.methodDescriptorPromise.succeed(methodDescriptor)
            context.fireChannelRead(self.wrapInboundOut(.metadata(metadata)))
          } else {
            assertionFailure("Method descriptor should have been present if we received metadata.")
          }

        case .rejectRPC(let trailers):
          self.flushPending = true
          self.methodDescriptorPromise.fail(
            RPCError(
              code: .unavailable,
              message: "RPC was rejected."
            )
          )
          let response = HTTP2Frame.FramePayload.headers(.init(headers: trailers, endStream: true))
          context.write(self.wrapOutboundOut(response), promise: nil)

        case .receivedStatusAndMetadata:
          throw RPCError(
            code: .internalError,
            message: "Server cannot get receivedStatusAndMetadata."
          )

        case .protocolViolation:
          context.writeAndFlush(self.wrapOutboundOut(.rstStream(.protocolError)), promise: nil)
          context.close(promise: nil)

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
    self.methodDescriptorPromise.fail(
      RPCError(
        code: .unavailable,
        message: "RPC stream was closed before we got any Metadata."
      )
    )
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
        self.flushPending = true
        let headers = try self.stateMachine.send(metadata: metadata)
        context.write(self.wrapOutboundOut(.headers(.init(headers: headers))), promise: promise)
      } catch {
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case .message(let message):
      do {
        try self.stateMachine.send(message: message, promise: promise)
      } catch {
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case .status(let status, let metadata):
      do {
        let headers = try self.stateMachine.send(status: status, metadata: metadata)
        let response = HTTP2Frame.FramePayload.headers(.init(headers: headers, endStream: true))
        self.pendingTrailers = (response, promise)
      } catch {
        promise?.fail(error)
        context.fireErrorCaught(error)
      }
    }
  }

  func flush(context: ChannelHandlerContext) {
    if self.isReading {
      // We don't want to flush yet if we're still in a read loop.
      return
    }

    do {
      loop: while true {
        switch try self.stateMachine.nextOutboundFrame() {
        case .sendFrame(let byteBuffer, let promise):
          self.flushPending = true
          context.write(
            self.wrapOutboundOut(.data(.init(data: .byteBuffer(byteBuffer)))),
            promise: promise
          )

        case .noMoreMessages:
          if let pendingTrailers = self.pendingTrailers {
            self.flushPending = true
            self.pendingTrailers = nil
            context.write(
              self.wrapOutboundOut(pendingTrailers.trailers),
              promise: pendingTrailers.promise
            )
          }
          break loop

        case .awaitMoreMessages:
          break loop
        }
      }

      if self.flushPending {
        self.flushPending = false
        context.flush()
      }
    } catch {
      context.fireErrorCaught(error)
    }
  }
}
