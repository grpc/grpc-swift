import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<GRPCStatus>
  fileprivate var eventObserver: EventObserver?
  
  fileprivate var hasReceivedRequest = false
  
  public private(set) var context: StreamingResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, headers: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    self.context = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, headers: headers)
    self.eventObserver = eventObserverFactory(context!)
    context!.statusPromise.futureResult.whenComplete {
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
      .cascade(promise: context!.statusPromise)
  }
}
