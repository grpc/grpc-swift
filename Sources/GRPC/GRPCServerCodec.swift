/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Foundation
import SwiftProtobuf
import NIO
import NIOFoundationCompat
import NIOHTTP1

/// Incoming gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerRequestPart<RequestMessage: Message> {
  case head(HTTPRequestHead)
  case message(RequestMessage)
  case end
}

/// Outgoing gRPC package with a fixed message type.
///
/// - Important: This is **NOT** part of the public API.
public enum _GRPCServerResponsePart<ResponseMessage: Message> {
  case headers(HTTPHeaders)
  case message(ResponseMessage)
  case statusAndTrailers(GRPCStatus, HTTPHeaders)
}

/// A simple channel handler that translates raw gRPC packets into decoded protobuf messages, and vice versa.
internal final class GRPCServerCodec<RequestMessage: Message, ResponseMessage: Message> {}

extension GRPCServerCodec: ChannelInboundHandler {
  typealias InboundIn = _RawGRPCServerRequestPart
  typealias InboundOut = _GRPCServerRequestPart<RequestMessage>

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      context.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    case .message(var message):
      let messageAsData = message.readData(length: message.readableBytes)!
      do {
        context.fireChannelRead(self.wrapInboundOut(.message(try RequestMessage(serializedData: messageAsData))))
      } catch {
        context.fireErrorCaught(GRPCError.DeserializationFailure().captureContext())
      }

    case .end:
      context.fireChannelRead(self.wrapInboundOut(.end))
    }
  }
}

extension GRPCServerCodec: ChannelOutboundHandler {
  typealias OutboundIn = _GRPCServerResponsePart<ResponseMessage>
  typealias OutboundOut = _RawGRPCServerResponsePart

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      context.write(self.wrapOutboundOut(.headers(headers)), promise: promise)

    case .message(let message):
      do {
        let messageData = try message.serializedData()
        context.write(self.wrapOutboundOut(.message(messageData)), promise: promise)
      } catch {
        let error = GRPCError.SerializationFailure().captureContext()
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case let .statusAndTrailers(status, trailers):
      context.writeAndFlush(self.wrapOutboundOut(.statusAndTrailers(status, trailers)), promise: promise)
    }
  }
}
