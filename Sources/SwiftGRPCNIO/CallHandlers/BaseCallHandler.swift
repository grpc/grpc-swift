import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Provides a means for decoding incoming gRPC messages into protobuf objects.
// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
public class BaseCallHandler<RequestMessage: Message, ResponseMessage: Message>: GRPCCallHandler, ChannelInboundHandler {
  public func makeGRPCServerCodec() -> ChannelHandler { return GRPCServerCodec<RequestMessage, ResponseMessage>() }

  public typealias InboundIn = GRPCServerRequestPart<RequestMessage>
  public typealias OutboundOut = GRPCServerResponsePart<ResponseMessage>

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .headers: preconditionFailure("should not have received headers")
    case .message(let message): processMessage(message)
    case .end: endOfStreamReceived()
    }
  }

  public func processMessage(_ message: RequestMessage) {
    fatalError("needs to be overridden")
  }

  public func endOfStreamReceived() { }
}
