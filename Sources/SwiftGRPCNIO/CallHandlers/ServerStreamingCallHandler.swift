import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Handles server-streaming calls. Calls the observer block with the request message.
// The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
// To close the call and send the status, complete the status future returned by the observer block.
public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<GRPCStatus>
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  //! FIXME: Do we need to keep the context around at all here?
  public private(set) var context: StreamingResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, headers: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, headers: headers)
    self.eventObserver = eventObserverFactory(context!)
    context!.statusPromise.futureResult.whenComplete {
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.context = nil
    }
  }
  
  
  public override func processMessage(_ message: RequestMessage) {
    guard !hasReceivedRequest else {
      //! FIXME: Better handle this error.
      print("multiple messages received on server-streaming call")
      return
    }
    hasReceivedRequest = true
    
    let resultFuture = self.eventObserver!(message)
    resultFuture
      // Fulfill the status promise with whatever status the framework user has provided.
      .cascade(promise: context!.statusPromise)
  }
}
