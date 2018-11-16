import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  public private(set) var context: UnaryResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, headers: HTTPRequestHead, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, headers: headers)
    self.eventObserver = eventObserverFactory(self.context!)
    context!.responsePromise.futureResult.whenComplete {
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
      .cascade(promise: context!.responsePromise)
  }
}
