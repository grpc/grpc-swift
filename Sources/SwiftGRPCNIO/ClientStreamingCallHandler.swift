import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public enum StreamEvent<Message: SwiftProtobuf.Message> {
  case message(Message)
  case end
}

public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias HandlerImplementation = (StreamEvent<RequestMessage>) -> Void
  fileprivate var handlerImplementation: HandlerImplementation?

  public init(eventLoop: EventLoop, handlerImplementationFactory: @escaping (EventLoopPromise<ResponseMessage>) -> HandlerImplementation) {
    super.init(eventLoop: eventLoop)

    self.handlerImplementation = handlerImplementationFactory(self.responsePromise)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.handlerImplementation = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    handlerImplementation?(.message(message))
  }

  public override func endOfStreamReceived() {
    handlerImplementation?(.end)
  }
}
