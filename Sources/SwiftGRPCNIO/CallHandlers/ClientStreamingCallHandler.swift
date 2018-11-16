import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public enum StreamEvent<Message: SwiftProtobuf.Message> {
  case message(Message)
  case end
  //! FIXME: Also support errors in this type, to propagate them to the event handler.
}

public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  fileprivate var eventObserver: EventLoopFuture<EventObserver>?
  
  public private(set) var context: UnaryResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, headers: HTTPRequestHead, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    super.init()
    self.context = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, headers: headers)
    self.eventObserver = eventObserverFactory(context!)
    self.eventObserver!.cascadeFailure(promise: context!.responsePromise)
    context!.responsePromise.futureResult.whenComplete {
      self.eventObserver = nil
      self.context = nil
    }
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
