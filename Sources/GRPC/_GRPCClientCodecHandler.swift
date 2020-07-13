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
import NIO

internal class GRPCClientCodecHandler<Serializer: MessageSerializer, Deserializer: MessageDeserializer> {
  /// The request serializer.
  private let serializer: Serializer

  /// The response deserializer.
  private let deserializer: Deserializer

  internal init(serializer: Serializer, deserializer: Deserializer) {
    self.serializer = serializer
    self.deserializer = deserializer
  }
}

extension GRPCClientCodecHandler: ChannelInboundHandler {
  typealias InboundIn = _RawGRPCClientResponsePart
  typealias InboundOut = _GRPCClientResponsePart<Deserializer.Output>

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .initialMetadata(let headers):
      context.fireChannelRead(self.wrapInboundOut(.initialMetadata(headers)))

    case .message(let messageContext):
      do {
        let response = try self.deserializer.deserialize(byteBuffer: messageContext.message)
        context.fireChannelRead(self.wrapInboundOut(.message(.init(response, compressed: messageContext.compressed))))
      } catch {
        context.fireErrorCaught(error)
      }

    case .trailingMetadata(let trailers):
      context.fireChannelRead(self.wrapInboundOut(.trailingMetadata(trailers)))

    case .status(let status):
      context.fireChannelRead(self.wrapInboundOut(.status(status)))
    }
  }
}

extension GRPCClientCodecHandler: ChannelOutboundHandler {
  typealias OutboundIn = _GRPCClientRequestPart<Serializer.Input>
  typealias OutboundOut = _RawGRPCClientRequestPart

  internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    switch self.unwrapOutboundIn(data) {
    case .head(let head):
      context.write(self.wrapOutboundOut(.head(head)), promise: promise)

    case .message(let message):
      do {
        let serialized = try self.serializer.serialize(message.message, allocator: context.channel.allocator)
        context.write(self.wrapOutboundOut(.message(.init(serialized, compressed: message.compressed))), promise: promise)
      } catch {
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case .end:
      context.write(self.wrapOutboundOut(.end), promise: promise)
    }
  }
}
