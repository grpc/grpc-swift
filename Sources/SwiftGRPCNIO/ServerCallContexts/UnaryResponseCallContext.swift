import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Abstract base class exposing a method that exposes a promise fot the RPC response.
// When `responsePromise` is fulfilled, the call is closed and the provided response transmitted with status `responseStatus` (`.ok` by default).
// If `statusPromise` is failed and the error is of type `GRPCStatus`, that error will be returned to the client.
// For other errors, `GRPCStatus.processingError` is returned to the client.
// For unary calls, the response is not actually provided by fulfilling `responsePromise`, but instead by completing
// the future returned by `UnaryCallHandler.EventObserver`.
//! FIXME: Should we create an additional variant of this that does not expose `responsePromise` for unary calls?
open class UnaryResponseCallContext<ResponseMessage: Message>: ServerCallContext {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let responsePromise: EventLoopPromise<ResponseMessage>
  public var responseStatus: GRPCStatus = .ok
  
  public override init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.responsePromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, headers: headers)
  }
}

// Concrete implementation of `UnaryResponseCallContext` used by our generated code.
open class UnaryResponseCallContextImpl<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> {
  public let channel: Channel
  
  public init(channel: Channel, headers: HTTPRequestHead) {
    self.channel = channel
    
    super.init(eventLoop: channel.eventLoop, headers: headers)
    
    responsePromise.futureResult
      .map { responseMessage in
        // Send the response provided to the promise.
        //! FIXME: It would be nicer to chain sending the status onto a successful write, but for some reason the
        //  "write message" future doesn't seem to get fulfilled?
        self.channel.write(NIOAny(WrappedResponse.message(responseMessage)), promise: nil)
        
        return self.responseStatus
      }
      // Ensure that any error provided is of type `GRPCStatus`, using "internal server error" as a fallback.
      .mapIfError { error in
        (error as? GRPCStatus) ?? .processingError
      }
      // Finish the call by returning the final status.
      .whenSuccess { status in
        self.channel.writeAndFlush(NIOAny(WrappedResponse.status(status)), promise: nil)
      }
  }
}

// Concrete implementation of `UnaryResponseCallContext` used for testing.
// Only provided to make it clear in tests that no "real" implementation is used.
open class UnaryResponseCallContextTestStub<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> { }
