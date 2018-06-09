import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: StatusSendingHandler<RequestMessage, ResponseMessage> {
  public typealias HandlerImplementation = (RequestMessage, ServerStreamingCallHandler<RequestMessage, ResponseMessage>) -> Void
  fileprivate var handlerImplementation: HandlerImplementation?

  fileprivate var hasReceivedRequest = false

  public init(eventLoop: EventLoop, handler: @escaping HandlerImplementation) {
    super.init(eventLoop: eventLoop)
    self.handlerImplementation = handler
    self.statusPromise.futureResult.whenComplete { [weak self] in
      self?.handlerImplementation = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    assert(!hasReceivedRequest, "multiple messages received on server-streaming call")
    hasReceivedRequest = true

    handlerImplementation?(message, self)
  }

  public func sendMessage(_ message: ResponseMessage) {
    ctx?.writeAndFlush(self.wrapOutboundOut(.message(message)), promise: nil)
  }

  public func sendStatus(_ status: GRPCStatus) {
    self.statusPromise.succeed(result: status)
  }
}
