import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias HandlerImplementation = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  fileprivate var handlerImplementation: HandlerImplementation?

  fileprivate var hasReceivedRequest = false

  public init(eventLoop: EventLoop, handlerImplementation: @escaping (RequestMessage) -> EventLoopFuture<ResponseMessage>) {
    super.init(eventLoop: eventLoop)

    self.handlerImplementation = handlerImplementation
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.handlerImplementation = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    assert(!hasReceivedRequest, "multiple messages received on unary call")
    hasReceivedRequest = true

    handlerImplementation?(message)
      .cascade(promise: responsePromise)
  }
}
