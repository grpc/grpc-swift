import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public enum StreamEvent<Message: SwiftProtobuf.Message> {
  case message(Message)
  case end
}

public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: UnaryResponseHandler<RequestMessage, ResponseMessage> {
  public typealias Handler = (StreamEvent<RequestMessage>) -> Void
  fileprivate var handler: Handler?

  public init(eventLoop: EventLoop, headers: HTTPHeaders, handlerFactory: (ClientStreamingCallHandler) -> Handler) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.handler = handlerFactory(self)
    self.responsePromise.futureResult.whenComplete { [weak self] in
      self?.handler = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    handler?(.message(message))
  }

  public override func endOfStreamReceived() {
    handler?(.end)
  }
}
