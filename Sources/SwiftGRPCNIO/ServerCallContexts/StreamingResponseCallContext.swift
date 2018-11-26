import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Abstract base class exposing a method to send multiple messages over the wire and a promise for the final RPC status.
///
/// - When `statusPromise` is fulfilled, the call is closed and the provided status transmitted.
/// - If `statusPromise` is failed and the error is of type `GRPCStatus`, that error will be returned to the client.
/// - For other errors, `GRPCStatus.processingError` is returned to the client.
open class StreamingResponseCallContext<ResponseMessage: Message>: ServerCallContext {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let statusPromise: EventLoopPromise<GRPCStatus>
  
  public override init(eventLoop: EventLoop, request: HTTPRequestHead) {
    self.statusPromise = eventLoop.newPromise()
    super.init(eventLoop: eventLoop, request: request)
  }
  
  open func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    fatalError("needs to be overridden")
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used by our generated code.
open class StreamingResponseCallContextImpl<ResponseMessage: Message>: StreamingResponseCallContext<ResponseMessage> {
  public let channel: Channel
  
  public init(channel: Channel, request: HTTPRequestHead) {
    self.channel = channel
    
    super.init(eventLoop: channel.eventLoop, request: request)
    
    statusPromise.futureResult
      // Ensure that any error provided is of type `GRPCStatus`, using "internal server error" as a fallback.
      .mapIfError { error in
        (error as? GRPCStatus) ?? .processingError
      }
      // Finish the call by returning the final status.
      .whenSuccess {
        self.channel.writeAndFlush(NIOAny(WrappedResponse.status($0)), promise: nil)
    }
  }
  
  open override func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    let promise: EventLoopPromise<Void> = eventLoop.newPromise()
    channel.writeAndFlush(NIOAny(WrappedResponse.message(message)), promise: promise)
    return promise.futureResult
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used for testing.
///
/// Simply records all sent messages.
open class StreamingResponseCallContextTestStub<ResponseMessage: Message>: StreamingResponseCallContext<ResponseMessage> {
  open var recordedResponses: [ResponseMessage] = []
  
  open override func sendResponse(_ message: ResponseMessage) -> EventLoopFuture<Void> {
    recordedResponses.append(message)
    return eventLoop.newSucceededFuture(result: ())
  }
}
