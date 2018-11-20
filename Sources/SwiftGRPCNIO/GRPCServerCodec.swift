import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public enum GRPCServerRequestPart<MessageType: Message> {
  case head(HTTPRequestHead)
  case message(MessageType)
  case end
}

public enum GRPCServerResponsePart<MessageType: Message> {
  case headers(HTTPHeaders)
  case message(MessageType)
  case status(GRPCStatus)
}

/// A simple channel handler that translates raw gRPC packets into decoded protobuf messages,
/// and vice versa.
public final class GRPCServerCodec<RequestMessage: Message, ResponseMessage: Message>: ChannelInboundHandler, ChannelOutboundHandler {
  public typealias InboundIn = RawGRPCServerRequestPart
  public typealias InboundOut = GRPCServerRequestPart<RequestMessage>

  public typealias OutboundIn = GRPCServerResponsePart<ResponseMessage>
  public typealias OutboundOut = RawGRPCServerResponsePart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      ctx.fireChannelRead(self.wrapInboundOut(.head(requestHead)))

    case .message(var messageData):
      //! FIXME: `import NIOFoundationCompat`, then use `readData` here.
      let allBytes = messageData.readBytes(length: messageData.readableBytes)!
      do {
        ctx.fireChannelRead(self.wrapInboundOut(.message(try RequestMessage(serializedData: Data(bytes: allBytes)))))
      } catch {
        //! FIXME: Ensure that the last handler in the pipeline returns `.dataLoss` here?
        ctx.fireErrorCaught(error)
      }

    case .end:
      ctx.fireChannelRead(self.wrapInboundOut(.end))
    }
  }

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .headers(let headers):
      ctx.write(self.wrapOutboundOut(.headers(headers)), promise: promise)
    case .message(let message):
      do {
        let messageData = try message.serializedData()
        var responseBuffer = ctx.channel.allocator.buffer(capacity: messageData.count)
        responseBuffer.write(bytes: messageData)
        ctx.write(self.wrapOutboundOut(.message(responseBuffer)), promise: promise)
      } catch {
        promise?.fail(error: error)
        ctx.fireErrorCaught(error)
      }
    case .status(let status):
      ctx.write(self.wrapOutboundOut(.status(status)), promise: promise)
    }
  }
}
