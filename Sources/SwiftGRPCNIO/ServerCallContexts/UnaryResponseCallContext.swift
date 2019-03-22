import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Abstract base class exposing a method that exposes a promise for the RPC response.
///
/// - When `responsePromise` is fulfilled, the call is closed and the provided response transmitted with status `responseStatus` (`.ok` by default).
/// - If `statusPromise` is failed and the error is of type `GRPCStatus`, that error will be returned to the client.
/// - For other errors, `GRPCStatus.processingError` is returned to the client.
///
/// For unary calls, the response is not actually provided by fulfilling `responsePromise`, but instead by completing
/// the future returned by `UnaryCallHandler.EventObserver`.
open class UnaryResponseCallContext<ResponseMessage: Message>: ServerCallContextBase, StatusOnlyCallContext {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let responsePromise: EventLoopPromise<ResponseMessage>
  public var responseStatus: GRPCStatus = .ok
  
  public override init(eventLoop: EventLoop, request: HTTPRequestHead) {
    self.responsePromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, request: request)
  }
}

/// Protocol variant of `UnaryResponseCallContext` that only exposes the `responseStatus` field, but not
/// `responsePromise`.
///
/// Motivation: `UnaryCallHandler` already asks the call handler return an `EventLoopFuture<ResponseMessage>` which
/// is automatically cascaded into `UnaryResponseCallContext.responsePromise`, so that promise does not (and should not)
/// be fulfilled by the user.
///
/// We can use a protocol (instead of an abstract base class) here because removing the generic `responsePromise` field
/// lets us avoid associated-type requirements on the protocol.
public protocol StatusOnlyCallContext: ServerCallContext {
  var responseStatus: GRPCStatus { get set }
}

/// Concrete implementation of `UnaryResponseCallContext` used by our generated code.
open class UnaryResponseCallContextImpl<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> {
  public let channel: Channel
  
  public init(channel: Channel, request: HTTPRequestHead) {
    self.channel = channel
    
    super.init(eventLoop: channel.eventLoop, request: request)
    
    responsePromise.futureResult
      .map { responseMessage in
        // Send the response provided to the promise.
        //! FIXME: It would be nicer to chain sending the status onto a successful write, but for some reason the
        //  "write message" future doesn't seem to get fulfilled?
        self.channel.writeAndFlush(NIOAny(WrappedResponse.message(responseMessage)), promise: nil)
        
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

/// Concrete implementation of `UnaryResponseCallContext` used for testing.
///
/// Only provided to make it clear in tests that no "real" implementation is used.
open class UnaryResponseCallContextTestStub<ResponseMessage: Message>: UnaryResponseCallContext<ResponseMessage> { }
