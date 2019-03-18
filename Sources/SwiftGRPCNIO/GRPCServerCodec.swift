import Foundation
import SwiftProtobuf
import NIO
import NIOFoundationCompat
import NIOHTTP1

/// Incoming gRPC package with a fixed message type.
public enum GRPCServerRequestPart<RequestMessage: Message> {
  case head(HTTPRequestHead)
  case message(RequestMessage)
  case end
}

/// Outgoing gRPC package with a fixed message type.
public enum GRPCServerResponsePart<ResponseMessage: Message> {
  case headers(HTTPHeaders)
  case message(ResponseMessage)
  case status(GRPCStatus)
}

/// A simple channel handler that translates raw gRPC packets into decoded protobuf messages, and vice versa.
public final class GRPCServerCodec<RequestMessage: Message, ResponseMessage: Message> {}

extension GRPCServerCodec: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCServerRequestPart
  public typealias InboundOut = GRPCServerRequestPart<RequestMessage>

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      context.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    case .message(var message):
      let messageAsData = message.readData(length: message.readableBytes)!
      do {
        context.fireChannelRead(self.wrapInboundOut(.message(try RequestMessage(serializedData: messageAsData))))
      } catch {
        context.fireErrorCaught(GRPCError.server(.requestProtoDeserializationFailure))
      }

    case .end:
      context.fireChannelRead(self.wrapInboundOut(.end))
    }
  }
}

extension GRPCServerCodec: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCServerResponsePart<ResponseMessage>
  public typealias OutboundOut = RawGRPCServerResponsePart

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      context.write(self.wrapOutboundOut(.headers(headers)), promise: promise)

    case .message(let message):
      do {
        let messageData = try message.serializedData()
        context.write(self.wrapOutboundOut(.message(messageData)), promise: promise)
      } catch {
        let error = GRPCError.server(.responseProtoSerializationFailure)
        promise?.fail(error)
        context.fireErrorCaught(error)
      }

    case .status(let status):
      context.writeAndFlush(self.wrapOutboundOut(.status(status)), promise: promise)
    }
  }
}
