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
  fileprivate var eventObserver: EventObserver?

  public init(eventLoop: EventLoop, headers: HTTPHeaders, eventObserverFactory: (ClientStreamingCallHandler) -> EventObserver) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.eventObserver = eventObserverFactory(self)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    eventObserver?(.message(message))
  }

  public override func endOfStreamReceived() {
    eventObserver?(.end)
  }
}
