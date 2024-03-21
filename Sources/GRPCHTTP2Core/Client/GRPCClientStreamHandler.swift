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
  typealias InboundOut = RPCResponsePart
  
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
}

// - MARK: ChannelInboundHandler

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension GRPCClientStreamHandler {
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    self.isReading = true
    let frame = self.unwrapInboundIn(data)
    switch frame {
    case .data(let frameData):
      let endStream = frameData.endStream
      switch frameData.data {
      case .byteBuffer(let buffer):
        do {
          try self.stateMachine.receive(buffer: buffer, endStream: endStream)
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
        case .receivedMetadata(let metadata):
          context.fireChannelRead(self.wrapInboundOut(.metadata(metadata)))
          
        case .rejectRPC(let trailers):
          throw RPCError(
            code: .internalError,
            message: "Server cannot get rejectRPC."
          )
          
        case .receivedStatusAndMetadata(let status, let metadata):
          context.fireChannelRead(self.wrapInboundOut(.status(status, metadata)))
          
        case .doNothing:
          ()
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
extension GRPCClientStreamHandler {
  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case .metadata(let metadata):
      do {
        self.flushPending = true
        let headers = try self.stateMachine.send(metadata: metadata)
        context.write(self.wrapOutboundOut(.headers(.init(headers: headers))), promise: nil)
        // TODO: move the promise handling into the state machine
        promise?.succeed()
      } catch {
        context.fireErrorCaught(error)
        // TODO: move the promise handling into the state machine
        promise?.fail(error)
      }
      
    case .message(let message):
      do {
        try self.stateMachine.send(message: message)
        // TODO: move the promise handling into the state machine
        promise?.succeed()
      } catch {
        context.fireErrorCaught(error)
        // TODO: move the promise handling into the state machine
        promise?.fail(error)
      }
    }
  }
  
  func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
    if case .output = mode {
      // We need to send an HTTP2 frame with the EOS flag set.
      do {
        try self.stateMachine.closeOutbound()
      } catch {
        context.fireErrorCaught(error)
      }
    } else {
      context.close(mode: mode, promise: promise)
    }
  }
  
  func flush(context: ChannelHandlerContext) {
    if self.isReading {
      // We don't want to flush yet if we're still in a read loop.
      return
    }
    
    do {
    loop: while true {
      switch try self.stateMachine.nextOutboundMessage() {
      case .sendMessage(let byteBuffer):
        self.flushPending = true
        context.write(
          self.wrapOutboundOut(.data(.init(data: .byteBuffer(byteBuffer)))),
          promise: nil
        )
        
      case .noMoreMessages:
        context.close(mode: .output, promise: nil)
        // This isn't enough, I'd have to send an empty framepayload with EOS set, but I've already sent an empty frame because I called .send(message:[], endStream: true) in close() above. The solution is to have a close() method on the state machine to decouple the message from the closing.
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