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

class GRPCServerCodecHandler<Serializer: MessageSerializer, Deserializer: MessageDeserializer> {
  /// The response serializer.
  private let serializer: Serializer

  /// The request deserializer.
  private let deserializer: Deserializer

  internal init(serializer: Serializer, deserializer: Deserializer) {
    self.serializer = serializer
    self.deserializer = deserializer
  }
}

extension GRPCServerCodecHandler: ChannelInboundHandler {
  typealias InboundIn = _RawGRPCServerRequestPart
  typealias InboundOut = _GRPCServerRequestPart<Deserializer.Output>

  internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case let .headers(head):
      context.fireChannelRead(self.wrapInboundOut(.headers(head)))

    case let .message(buffer):
      do {
        let deserialized = try self.deserializer.deserialize(byteBuffer: buffer)
        context.fireChannelRead(self.wrapInboundOut(.message(deserialized)))
      } catch {
        context.fireErrorCaught(error)
      }

    case .end:
      context.fireChannelRead(self.wrapInboundOut(.end))
    }
  }
}

extension GRPCServerCodecHandler: ChannelOutboundHandler {
  typealias OutboundIn = _GRPCServerResponsePart<Serializer.Input>
  typealias OutboundOut = _RawGRPCServerResponsePart

  internal func write(
    context: ChannelHandlerContext,
    data: NIOAny,
    promise: EventLoopPromise<Void>?
  ) {
    switch self.unwrapOutboundIn(data) {
    case let .headers(headers):
      context.write(self.wrapOutboundOut(.headers(headers)), promise: promise)

    case let .message(messageContext):
      do {
        let buffer = try self.serializer.serialize(
          messageContext.message,
          allocator: context.channel.allocator
        )
        context.write(
          self.wrapOutboundOut(.message(.init(buffer, compressed: messageContext.compressed))),
          promise: promise
        )
      } catch {
        let error = GRPCError.SerializationFailure().captureContext()
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case let .statusAndTrailers(status, trailers):
      context.write(self.wrapOutboundOut(.statusAndTrailers(status, trailers)), promise: promise)
    }
  }
}
