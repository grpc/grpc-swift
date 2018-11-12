import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias Handler = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  fileprivate var handler: Handler?

  fileprivate var hasReceivedRequest = false

  public init(eventLoop: EventLoop, headers: HTTPHeaders, handlerFactory: (UnaryCallHandler) -> Handler) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.handler = handlerFactory(self)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.handler = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    assert(!hasReceivedRequest, "multiple messages received on unary call")
    hasReceivedRequest = true

    handler?(message)
      .cascade(promise: responsePromise)
  }
}
