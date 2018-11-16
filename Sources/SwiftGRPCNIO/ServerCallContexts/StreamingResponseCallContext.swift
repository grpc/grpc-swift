import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

open class StreamingResponseCallContext<ResponseMessage: Message>: ServerCallContext {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let statusPromise: EventLoopPromise<GRPCStatus>
  
  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.statusPromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, headers: headers)
  }
  
  open func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    fatalError("needs to be overridden")
  }
}

open class StreamingResponseCallContextImpl<ResponseMessage: Message>: StreamingResponseCallContext<ResponseMessage> {
  public let channel: Channel
  
  public init(channel: Channel, headers: HTTPRequestHead) {
    self.channel = channel
    
    super.init(eventLoop: channel.eventLoop, headers: headers)
    
    statusPromise.futureResult
      .mapIfError { ($0 as? GRPCStatus) ?? .processingError }
      .whenSuccess {
        self.channel.writeAndFlush(NIOAny(WrappedResponse.status($0)), promise: nil)
    }
  }
  
  open override func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    let promise: EventLoopPromise<Void> = eventLoop.newPromise()
    channel.writeAndFlush(NIOAny(WrappedResponse.message(message)), promise: promise)
    return promise.futureResult
  }
}

open class StreamingResponseCallContextTestStub<ResponseMessage: Message>: StreamingResponseCallContext<ResponseMessage> {
  open var recordedResponses: [ResponseMessage] = []
  
  open override func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    recordedResponses.append(message)
    return eventLoop.newSucceededFuture(result: ())
  }
}
