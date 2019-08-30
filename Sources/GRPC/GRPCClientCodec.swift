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
import Logging

/// Outgoing gRPC package with a fixed message type.
public enum GRPCClientRequestPart<RequestMessage: Message> {
  case head(HTTPRequestHead)
  // We box the message to keep the enum small enough to fit in `NIOAny` and avoid unnecessary
  // allocations.
  case message(_Box<RequestMessage>)
  case end
}

/// Incoming gRPC package with a fixed message type.
public enum GRPCClientResponsePart<ResponseMessage: Message> {
  case headers(HTTPHeaders)
  // We box the message to keep the enum small enough to fit in `NIOAny` and avoid unnecessary
  // allocations.
  case message(_Box<ResponseMessage>)
  case status(GRPCStatus, HTTPHeaders?)
}

/// This channel handler simply encodes and decodes protobuf messages into typed messages
/// and `Data`.
public final class GRPCClientCodec<RequestMessage: Message, ResponseMessage: Message> {
  private let logger: Logger

  public init(logger: Logger) {
    var loggerWithMetadata = logger
    loggerWithMetadata[metadataKey: MetadataKey.channelHandler] = "GRPCClientCodec"
    self.logger = loggerWithMetadata
  }
}

extension GRPCClientCodec: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCClientResponsePart
  public typealias InboundOut = GRPCClientResponsePart<ResponseMessage>

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let response = self.unwrapInboundIn(data)

    switch response {
    case .headers(let headers):
      self.logger.debug("read response headers: \(headers)")
      context.fireChannelRead(self.wrapInboundOut(.headers(headers)))

    case .message(var messageBuffer):
      self.logger.debug("read message \(messageBuffer)")
      // Force unwrapping is okay here; we're reading the readable bytes.
      let messageAsData = messageBuffer.readData(length: messageBuffer.readableBytes)!
      do {
        self.logger.debug("deserializing \(messageAsData.count) bytes as \(ResponseMessage.self)")
        let box = _Box(try ResponseMessage(serializedData: messageAsData))
        context.fireChannelRead(self.wrapInboundOut(.message(box)))
      } catch {
        context.fireErrorCaught(GRPCError.client(.responseProtoDeserializationFailure))
      }

    case let .statusAndTrailers(status, trailers):
      self.logger.debug("read status \(status)")
      context.fireChannelRead(self.wrapInboundOut(.status(status, trailers)))
    }
  }
}

extension GRPCClientCodec: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCClientRequestPart<RequestMessage>
  public typealias OutboundOut = RawGRPCClientRequestPart

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let request = self.unwrapOutboundIn(data)

    switch request {
    case .head(let head):
      self.logger.debug("writing request head: \(head)")
      context.write(self.wrapOutboundOut(.head(head)), promise: promise)

    case .message(let box):
      do {
        self.logger.debug("serializing and writing \(RequestMessage.self) protobuf")
        context.write(self.wrapOutboundOut(.message(try box.value.serializedData())), promise: promise)
      } catch {
        self.logger.error("failed to serialize message: \(box.value)")
        let error = GRPCError.client(.requestProtoSerializationFailure)
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case .end:
      self.logger.debug("writing end")
      context.write(self.wrapOutboundOut(.end), promise: promise)
    }
  }
}
