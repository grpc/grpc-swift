import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Handles unary calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and returns a future containing the call result.
/// - To return a response to the client, the framework user should complete that future
/// (similar to e.g. serving regular HTTP requests in frameworks such as Vapor).
public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  private var eventObserver: EventObserver?
  
  private var context: UnaryResponseCallContext<ResponseMessage>?
  
  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init(errorDelegate: errorDelegate)
    let context = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, request: request)
    self.context = context
    self.eventObserver = eventObserverFactory(context)
    context.responsePromise.futureResult.whenComplete {
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.context = nil
    }
  }
  
  public override func processMessage(_ message: RequestMessage) throws {
    guard let eventObserver = self.eventObserver,
      let context = self.context else {
      throw GRPCServerError.requestCardinalityViolation
    }
    
    let resultFuture = eventObserver(message)
    resultFuture
      // Fulfill the response promise with whatever response (or error) the framework user has provided.
      .cascade(promise: context.responsePromise)
    self.eventObserver = nil
  }
}
