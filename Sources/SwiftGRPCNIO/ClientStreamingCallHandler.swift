import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public enum StreamEvent<Message: SwiftProtobuf.Message> {
  case message(Message)
  case end
}

public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  fileprivate var eventObserver: EventLoopFuture<EventObserver>?

  public init(eventLoop: EventLoop, headers: HTTPRequestHead, eventObserverFactory: (ClientStreamingCallHandler) -> EventLoopFuture<EventObserver>) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.eventObserver = eventObserverFactory(self)
    self.eventObserver?.cascadeFailure(promise: self.responsePromise)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
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
