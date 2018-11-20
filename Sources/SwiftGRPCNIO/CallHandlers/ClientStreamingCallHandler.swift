import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Handles client-streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
// The observer block is implemented by the framework user and fulfills `context.responsePromise` when done.
public class ClientStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  fileprivate var eventObserver: EventLoopFuture<EventObserver>?
  
  //! FIXME: Do we need to keep the context around at all here?
  public private(set) var context: UnaryResponseCallContext<ResponseMessage>?
  
  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  public init(channel: Channel, request: HTTPRequestHead, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    super.init()
    self.context = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, request: request)
    self.eventObserver = eventObserverFactory(context!)
    // Terminate the call if no observer is provided.
    self.eventObserver!.cascadeFailure(promise: context!.responsePromise)
    context!.responsePromise.futureResult.whenComplete {
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
