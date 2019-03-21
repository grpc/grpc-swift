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
public enum GRPCClientRequestPart<RequestMessage: Message> {
  case head(HTTPRequestHead)
  case message(RequestMessage)
  case end
}

/// Incoming gRPC package with a fixed message type.
public enum GRPCClientResponsePart<ResponseMessage: Message> {
  case headers(HTTPHeaders)
  case message(ResponseMessage)
  case status(GRPCStatus)
}

/// This channel handler simply encodes and decodes protobuf messages into typed messages
/// and `Data`.
public final class GRPCClientCodec<RequestMessage: Message, ResponseMessage: Message> {
  public init() {}
}

extension GRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCClientResponsePart
  public typealias InboundOut = GRPCClientResponsePart<ResponseMessage>

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    let response = self.unwrapInboundIn(data)

    switch response {
    case .headers(let headers):
      ctx.fireChannelRead(self.wrapInboundOut(.headers(headers)))

    case .message(var messageBuffer):
      // Force unwrapping is okay here; we're reading the readable bytes.
      let messageAsData = messageBuffer.readData(length: messageBuffer.readableBytes)!
      do {
        ctx.fireChannelRead(self.wrapInboundOut(.message(try ResponseMessage(serializedData: messageAsData))))
      } catch {
        ctx.fireErrorCaught(GRPCError.client(.responseProtoDeserializationFailure))
      }

    case .status(let status):
      ctx.fireChannelRead(self.wrapInboundOut(.status(status)))
    }
  }
}

extension GRPCClientCodec: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart<RequestMessage>
  public typealias OutboundOut = RawGRPCClientRequestPart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let request = self.unwrapOutboundIn(data)

    switch request {
    case .head(let head):
      ctx.write(self.wrapOutboundOut(.head(head)), promise: promise)

    case .message(let message):
      do {
        ctx.write(self.wrapOutboundOut(.message(try message.serializedData())), promise: promise)
      } catch {
        let error = GRPCError.client(.requestProtoSerializationFailure)
        promise?.fail(error: error)
        ctx.fireErrorCaught(error)
      }

    case .end:
      ctx.write(self.wrapOutboundOut(.end), promise: promise)
    }
  }
}
