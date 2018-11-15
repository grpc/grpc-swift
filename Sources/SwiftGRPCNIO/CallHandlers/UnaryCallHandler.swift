import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  public private(set) var context: UnaryResponseCallContext<ResponseMessage>?
  
  public init(eventLoop: EventLoop, headers: HTTPRequestHead, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = UnaryResponseCallContextImpl<ResponseMessage>(eventLoop: eventLoop, headers: headers)
    self.eventObserver = eventObserverFactory(self.context!)
    context!.responsePromise.futureResult.whenComplete { [weak self] in
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
    
    let resultFuture = self.eventObserver!(message)
    resultFuture
      .cascade(promise: context!.responsePromise)
  }
}
