import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Handles unary calls. Calls the observer block with the request message.
// The observer block is implemented by the framework user and returns a future containing the call result.
// To return a response to the client, the framework user should complete that framework
// (similar to e.g. serving regular HTTP requests in frameworks such as Vapor).
public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  //! FIXME: Do we need to keep the context around at all here?
  public private(set) var context: UnaryResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, headers: HTTPRequestHead, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, headers: headers)
    self.eventObserver = eventObserverFactory(self.context!)
    context!.responsePromise.futureResult.whenComplete {
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.context = nil
    }
  }
  
  public override func processMessage(_ message: RequestMessage) {
    guard !hasReceivedRequest else {
      //! FIXME: Better handle this error.
      print("multiple messages received on unary call")
      return
    }
    hasReceivedRequest = true
    
    let resultFuture = self.eventObserver!(message)
    resultFuture
      // Fulfill the response promise with whatever response (or error) the framework user has provided.
      .cascade(promise: context!.responsePromise)
  }
}
