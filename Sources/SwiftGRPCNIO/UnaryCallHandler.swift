import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> Void
  fileprivate var eventObserver: EventObserver?

  fileprivate var hasReceivedRequest = false

  public init(eventLoop: EventLoop, headers: HTTPRequestHead, eventObserverFactory: (UnaryCallHandler) -> EventObserver) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.eventObserver = eventObserverFactory(self)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    assert(!hasReceivedRequest, "multiple messages received on unary call")
    hasReceivedRequest = true

    eventObserver?(message)
  }
}
