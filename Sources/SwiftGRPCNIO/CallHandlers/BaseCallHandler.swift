import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Provides a means for decoding incoming gRPC messages into protobuf objects.
///
/// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
public class BaseCallHandler<RequestMessage: Message, ResponseMessage: Message>: GRPCCallHandler {
  public func makeGRPCServerCodec() -> ChannelHandler { return GRPCServerCodec<RequestMessage, ResponseMessage>() }
  
  /// Called whenever a message has been received.
  ///
  /// Overridden by subclasses.
  public func processMessage(_ message: RequestMessage) {
    fatalError("needs to be overridden")
  }
  
  /// Called when the client has half-closed the stream, indicating that they won't send any further data.
  ///
  /// Overridden by subclasses if the "end-of-stream" event is relevant.
  public func endOfStreamReceived() { }
}

extension BaseCallHandler: ChannelInboundHandler {
  public typealias InboundIn = GRPCServerRequestPart<RequestMessage>
  public typealias OutboundOut = GRPCServerResponsePart<ResponseMessage>

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head: preconditionFailure("should not have received headers")
    case .message(let message): processMessage(message)
    case .end: endOfStreamReceived()
    }
  }
}
