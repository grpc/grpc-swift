import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: StatusSendingHandler<RequestMessage, ResponseMessage> {
  public typealias Handler = (StreamEvent<RequestMessage>) -> Void
  fileprivate var handler: Handler?

  public init(eventLoop: EventLoop, headers: HTTPHeaders, handlerFactory: (BidirectionalStreamingCallHandler) -> Handler) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.handler = handlerFactory(self)
    self.statusPromise.futureResult.whenComplete { [weak self] in
      self?.handler = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    handler?(.message(message))
  }

  public override func endOfStreamReceived() {
    handler?(.end)
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
