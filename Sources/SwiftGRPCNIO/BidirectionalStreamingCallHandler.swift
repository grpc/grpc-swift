import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: StatusSendingHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  fileprivate var eventObserver: EventObserver?

  public init(eventLoop: EventLoop, headers: HTTPHeaders, eventObserverFactory: (BidirectionalStreamingCallHandler) -> EventObserver) {
    super.init(eventLoop: eventLoop, headers: headers)

    self.eventObserver = eventObserverFactory(self)
    self.statusPromise.futureResult.whenComplete { [weak self] in
      self?.eventObserver = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    eventObserver?(.message(message))
  }

  public override func endOfStreamReceived() {
    eventObserver?(.end)
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
