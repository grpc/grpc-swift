import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Handles bidirectional streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
/// - To close the call and send the status, fulfill `context.statusPromise`.
public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  private var eventObserver: EventLoopFuture<EventObserver>?
  
  private var context: StreamingResponseCallContext<ResponseMessage>?

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  public init(channel: Channel, request: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    super.init()
    let context = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, request: request)
    self.context = context
    let eventObserver = eventObserverFactory(context)
    self.eventObserver = eventObserver
    // Terminate the call if no observer is provided.
    eventObserver.cascadeFailure(promise: context.statusPromise)
    context.statusPromise.futureResult.whenComplete {
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.context = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) {
    eventObserver?.whenSuccess { observer in
      observer(.message(message))
    }
  }

  public override func endOfStreamReceived() {
    eventObserver?.whenSuccess { observer in
      observer(.end)
    }
  }
}
