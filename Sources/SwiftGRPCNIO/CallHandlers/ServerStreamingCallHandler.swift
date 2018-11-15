import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> Void
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  public private(set) var context: StreamingResponseCallContext<ResponseMessage>?
  
  public init(eventLoop: EventLoop, headers: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = StreamingResponseCallContextImpl<ResponseMessage>(eventLoop: eventLoop, headers: headers)
    self.eventObserver = eventObserverFactory(context!)
    context!.statusPromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
      self?.context = nil
    }
  }
  
  public override func handlerAdded(ctx: ChannelHandlerContext) {
    context?.ctx = ctx
  }
  
  public override func processMessage(_ message: RequestMessage) {
    assert(!hasReceivedRequest, "multiple messages received on server-streaming call")
    hasReceivedRequest = true
    
    eventObserver?(message)
  }
}
