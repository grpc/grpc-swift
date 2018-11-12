import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Exposes a promise that should be fulfilled when it is time to return a unary response (for unary and client-streaming
// calls) to the client. Also see `StatusSendingHandler`.
public class UnaryResponseHandler<RequestMessage: Message, ResponseMessage: Message>: StatusSendingHandler<RequestMessage, ResponseMessage> {
  public let responsePromise: EventLoopPromise<ResponseMessage>
  public var responseStatus: GRPCStatus = .ok

  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    responsePromise = eventLoop.newPromise()

    super.init(eventLoop: eventLoop, headers: headers)
  }

  override public func handlerAdded(ctx: ChannelHandlerContext) {
    super.handlerAdded(ctx: ctx)

    responsePromise.futureResult
      .map { [weak self] responseMessage in
        guard let strongSelf = self,
          let ctx = strongSelf.ctx
          else { return GRPCStatus.processingError }

        //! FIXME: It would be nicer to chain sending the status onto a successful write, but for some reason the
        //  "write message" future doesn't seem to get fulfilled?
        ctx.write(strongSelf.wrapOutboundOut(.message(responseMessage)), promise: nil)

        return strongSelf.responseStatus
      }
      .cascade(promise: statusPromise)
  }
}
