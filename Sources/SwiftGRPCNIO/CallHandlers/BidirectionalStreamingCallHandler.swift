import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  fileprivate var eventObserver: EventLoopFuture<EventObserver>?
  
  public private(set) var context: StreamingResponseCallContext<ResponseMessage>?

  public init(eventLoop: EventLoop, headers: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    super.init()
    self.context = StreamingResponseCallContextImpl<ResponseMessage>(eventLoop: eventLoop, headers: headers)
    self.eventObserver = eventObserverFactory(context!)
    self.eventObserver?.cascadeFailure(promise: context!.statusPromise)
    context!.statusPromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
      self?.context = nil
    }
  }
  
  public override func handlerAdded(ctx: ChannelHandlerContext) {
    context?.ctx = ctx
  }

  public override func processMessage(_ message: RequestMessage) {
    eventObserver?.whenSuccess { observer in
      observer(.message(message))
    }
  }

  public override func endOfStreamReceived() {
    eventObserver?.whenSuccess { observer in
      observer(.end)
    }
  }
}
