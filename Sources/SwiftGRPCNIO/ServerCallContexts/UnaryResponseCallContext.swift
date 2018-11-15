import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

open class UnaryResponseCallContext<ResponseMessage: Message>: ServerCallContext<ResponseMessage> {
  public let responsePromise: EventLoopPromise<ResponseMessage>
  public var responseStatus: GRPCStatus = .ok
  
  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.responsePromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, headers: headers)
  }
  
  open func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    fatalError("needs to be overridden")
  }
}

open class UnaryResponseCallContextImpl<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> {
  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    super.init(eventLoop: eventLoop, headers: headers)
    
    responsePromise.futureResult
      .map { [weak self] responseMessage in
        guard let strongSelf = self,
          let ctx = strongSelf.ctx
          else { return GRPCStatus.processingError }
        
        //! FIXME: It would be nicer to chain sending the status onto a successful write, but for some reason the
        //  "write message" future doesn't seem to get fulfilled?
        ctx.write(NIOAny(WrappedResponse.message(responseMessage)), promise: nil)
        
        return strongSelf.responseStatus
      }
      .mapIfError { ($0 as? GRPCStatus) ?? .processingError }
      .whenSuccess { [weak self] in
        if let strongSelf = self,
          let ctx = strongSelf.ctx {
          ctx.writeAndFlush(NIOAny(WrappedResponse.status($0)), promise: nil)
        }
      }
  }
}

open class UnaryResponseCallContextTestStub<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> { }
