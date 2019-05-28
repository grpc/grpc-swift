import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Handles bidirectional streaming calls. Forwards incoming messages and end-of-stream events to the observer block.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
///   If the framework user wants to return a call error (e.g. in case of authentication failure),
///   they can fail the observer block future.
/// - To close the call and send the status, complete `context.statusPromise`.
public class BidirectionalStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (StreamEvent<RequestMessage>) -> Void
  private var eventObserver: EventLoopFuture<EventObserver>?

  private var callContext: StreamingResponseCallContext<ResponseMessage>?

  // We ask for a future of type `EventObserver` to allow the framework user to e.g. asynchronously authenticate a call.
  // If authentication fails, they can simply fail the observer future, which causes the call to be terminated.
  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventLoopFuture<EventObserver>) {
    super.init(errorDelegate: errorDelegate)
    let context = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, request: request, errorDelegate: errorDelegate)
    self.callContext = context
    let eventObserver = eventObserverFactory(context)
    self.eventObserver = eventObserver
    context.statusPromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.callContext = nil
    }
  }

  public override func handlerAdded(context: ChannelHandlerContext) {
    guard let eventObserver = self.eventObserver,
      let callContext = self.callContext else { return }
    // Terminate the call if the future providing an observer fails.
    // This is being done _after_ we have been added as a handler to ensure that the `GRPCServerCodec` required to
    // translate our outgoing `GRPCServerResponsePart<ResponseMessage>` message is already present on the channel.
    // Otherwise, our `OutboundOut` type would not match the `OutboundIn` type of the next handler on the channel.
    eventObserver.cascadeFailure(to: callContext.statusPromise)
  }


  public override func processMessage(_ message: RequestMessage) {
    self.eventObserver?.whenSuccess { observer in
      observer(.message(message))
    }
  }

  public override func endOfStreamReceived() throws {
    self.eventObserver?.whenSuccess { observer in
      observer(.end)
    }
  }

  override func sendErrorStatus(_ status: GRPCStatus) {
    self.callContext?.statusPromise.fail(status)
  }
}
