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
import NIO
import NIOHTTP1
import SwiftProtobuf

/// Outgoing gRPC package with a fixed message type.
public enum GRPCClientRequestPart<MessageType: Message> {
  case head(HTTPRequestHead)
  case message(MessageType)
  case end
}

/// Incoming gRPC package with a fixed message type.
public enum GRPCClientResponsePart<MessageType: Message> {
  case headers(HTTPHeaders)
  case message(MessageType)
  case status(GRPCStatus)
}

public final class RawGRPCToGRPCCodec<RequestMessage: Message, ResponseMessage: Message> {
  public init() {}
}

extension RawGRPCToGRPCCodec: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCClientResponsePart
  public typealias InboundOut = GRPCClientResponsePart<ResponseMessage>

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    let response = unwrapInboundIn(data)

    switch response {
    case .headers(let headers):
      ctx.fireChannelRead(wrapInboundOut(.headers(headers)))

    case .message(var message):
      let messageAsData = message.readData(length: message.readableBytes)!
      do {
        ctx.fireChannelRead(self.wrapInboundOut(.message(try ResponseMessage(serializedData: messageAsData))))
      } catch {
        ctx.fireErrorCaught(error)
      }

    case .status(let status):
      ctx.fireChannelRead(wrapInboundOut(.status(status)))
    }
  }
}

extension RawGRPCToGRPCCodec: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart<RequestMessage>
  public typealias OutboundOut = RawGRPCClientRequestPart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let request = unwrapOutboundIn(data)

    switch request {
    case .head(let head):
      ctx.write(wrapOutboundOut(.head(head)), promise: promise)

    case .message(let message):
      do {
        let messageAsData = try message.serializedData()
        var buffer = ctx.channel.allocator.buffer(capacity: messageAsData.count)
        buffer.write(bytes: messageAsData)
        ctx.write(wrapOutboundOut(.message(buffer)), promise: promise)
      } catch {
        print(error)
        ctx.fireErrorCaught(error)
      }

    case .end:
      ctx.writeAndFlush(wrapOutboundOut(.end), promise: promise)
    }
  }
}
