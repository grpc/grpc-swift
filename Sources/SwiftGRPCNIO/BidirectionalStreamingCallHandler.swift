import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: StatusSendingHandler<RequestMessage, ResponseMessage> {
  public typealias HandlerImplementation = (StreamEvent<RequestMessage>) -> Void
  fileprivate var handlerImplementation: HandlerImplementation?

  public init(eventLoop: EventLoop, handlerImplementationFactory: (BidirectionalStreamingCallHandler<RequestMessage, ResponseMessage>) -> HandlerImplementation) {
    super.init(eventLoop: eventLoop)

    self.handlerImplementation = handlerImplementationFactory(self)
    self.statusPromise.futureResult.whenComplete { [weak self] in
      self?.handlerImplementation = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    handlerImplementation?(.message(message))
  }

  public override func endOfStreamReceived() {
    handlerImplementation?(.end)
  }

  public func sendMessage(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    let promise: EventLoopPromise<Void> = eventLoop.newPromise()
    ctx?.writeAndFlush(self.wrapOutboundOut(.message(message)), promise: promise)
    return promise.futureResult
  }

  public func sendStatus(_ status: GRPCStatus) {
    self.statusPromise.succeed(result: status)
  }
}
