import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Handles unary calls. Calls the observer block with the request message.
///
/// - The observer block is implemented by the framework user and returns a future containing the call result.
/// - To return a response to the client, the framework user should complete that future
///   (similar to e.g. serving regular HTTP requests in frameworks such as Vapor).
public class UnaryCallHandler<RequestMessage: Message, ResponseMessage: Message>: BaseCallHandler<RequestMessage, ResponseMessage> {
  public typealias EventObserver = (RequestMessage) -> EventLoopFuture<ResponseMessage>
  private var eventObserver: EventObserver?

  private var callContext: UnaryResponseCallContext<ResponseMessage>?

  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, eventObserverFactory: (UnaryResponseCallContext<ResponseMessage>) -> EventObserver) {
    super.init(errorDelegate: errorDelegate)
    let callContext = UnaryResponseCallContextImpl<ResponseMessage>(channel: channel, request: request)
    self.callContext = callContext
    self.eventObserver = eventObserverFactory(callContext)
    callContext.responsePromise.futureResult.whenComplete { _ in
      // When done, reset references to avoid retain cycles.
      self.eventObserver = nil
      self.callContext = nil
    }
  }

  public override func processMessage(_ message: RequestMessage) throws {
    guard let eventObserver = self.eventObserver,
      let context = self.callContext else {
      throw GRPCError.server(.tooManyRequests)
    }

    let resultFuture = eventObserver(message)
    resultFuture
      // Fulfill the response promise with whatever response (or error) the framework user has provided.
      .cascade(to: context.responsePromise)
    self.eventObserver = nil
  }
  
  public override func endOfStreamReceived() throws {
    if self.eventObserver != nil {
      throw GRPCError.server(.noRequestsButOneExpected)
    }
  }
  
  override func sendErrorStatus(_ status: GRPCStatus) {
    callContext?.responsePromise.fail(status)
  }
}
