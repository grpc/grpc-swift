import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

open class UnaryResponseCallContext<ResponseMessage: Message>: ServerCallContext {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let responsePromise: EventLoopPromise<ResponseMessage>
  public var responseStatus: GRPCStatus = .ok
  
  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.responsePromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, headers: headers)
  }
}

open class UnaryResponseCallContextImpl<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> {
  public let channel: Channel
  
  public init(channel: Channel, headers: HTTPRequestHead) {
    self.channel = channel
    
    super.init(eventLoop: channel.eventLoop, headers: headers)
    
    responsePromise.futureResult
      .map { responseMessage in
        //! FIXME: It would be nicer to chain sending the status onto a successful write, but for some reason the
        //  "write message" future doesn't seem to get fulfilled?
        self.channel.write(NIOAny(WrappedResponse.message(responseMessage)), promise: nil)
        
        return self.responseStatus
      }
      .mapIfError { ($0 as? GRPCStatus) ?? .processingError }
      .whenSuccess {
        self.channel.writeAndFlush(NIOAny(WrappedResponse.status($0)), promise: nil)
      }
  }
}

open class UnaryResponseCallContextTestStub<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> { }
