import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Handles server-streaming calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and calls `context.sendResponse` as needed.
/// - To close the call and send the status, complete the status future returned by the observer block.
public class ServerStreamingCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<GRPCStatus>
  private var eventObserver: EventObserver?
  
  private var context: StreamingResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, request: HTTPRequestHead, eventObserverFactory: (StreamingResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init()
    let context = StreamingResponseCallContextImpl<ResponseMessage>(channel: channel, request: request)
    self.context = context
    self.eventObserver = eventObserverFactory(context)
    context.statusPromise.futureResult.whenComplete {
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.context = nil
    }
  }
  
  
  public override func processMessage(_ message: RequestMessage) {
    guard let eventObserver = self.eventObserver,
      let context = self.context else {
      //! FIXME: Better handle this error?
      print("multiple messages received on unary call")
      return
    }
    
    let resultFuture = eventObserver(message)
    resultFuture
      // Fulfill the status promise with whatever status the framework user has provided.
      .cascade(promise: context.statusPromise)
    self.eventObserver = nil
  }
}
