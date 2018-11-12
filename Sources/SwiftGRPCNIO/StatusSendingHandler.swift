import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Provides a means for decoding incoming gRPC messages into protobuf objects, and exposes a promise that should be
// fulfilled when it is time to return a status to the client.
// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
public class StatusSendingHandler<RequestMessage: Message, ResponseMessage: Message>: GRPCCallHandler, ChannelInboundHandler {
  public func makeGRPCServerCodec() -> ChannelHandler { return GRPCServerCodec<RequestMessage, ResponseMessage>() }

  public typealias InboundIn = GRPCServerRequestPart<RequestMessage>
  public typealias OutboundOut = GRPCServerResponsePart<ResponseMessage>

  let statusPromise: EventLoopPromise<GRPCStatus>
  public let eventLoop: EventLoop

  public let headers: HTTPRequestHead
  
  private(set) weak var ctx: ChannelHandlerContext?

  public init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.statusPromise = eventLoop.newPromise()
    
    self.headers = headers
  }

  public func handlerAdded(ctx: ChannelHandlerContext) {
    self.ctx = ctx

    statusPromise.futureResult
      .mapIfError { ($0 as? GRPCStatus) ?? .processingError }
      .whenSuccess { [weak self] in
        if let strongSelf = self,
          let ctx = strongSelf.ctx {
          ctx.writeAndFlush(strongSelf.wrapOutboundOut(.status($0)), promise: nil)
        }
    }
  }

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
