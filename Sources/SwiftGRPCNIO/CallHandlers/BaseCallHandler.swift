import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Provides a means for decoding incoming gRPC messages into protobuf objects.
///
/// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
public class BaseCallHandler<RequestMessage: Message, ResponseMessage: Message>: GRPCCallHandler {
  public func makeGRPCServerCodec() -> ChannelHandler { return GRPCServerCodec<RequestMessage, ResponseMessage>() }

  /// Called whenever a message has been received.
  ///
  /// Overridden by subclasses.
  public func processMessage(_ message: RequestMessage) throws {
    fatalError("needs to be overridden")
  }

  /// Called when the client has half-closed the stream, indicating that they won't send any further data.
  ///
  /// Overridden by subclasses if the "end-of-stream" event is relevant.
  public func endOfStreamReceived() { }

  /// Whether this handler can still write messages to the client.
  private var serverCanWrite = true

  /// Called for each error recieved in `errorCaught(ctx:error:)`.
  private weak var errorDelegate: ServerErrorDelegate?

  public init(errorDelegate: ServerErrorDelegate?) {
    self.errorDelegate = errorDelegate
  }
}

extension BaseCallHandler: ChannelInboundHandler {
  public typealias InboundIn = GRPCServerRequestPart<RequestMessage>

  /// Passes errors to the user-provided `errorHandler`. After an error has been received an
  /// appropriate status is written. Errors which don't conform to `GRPCStatusTransformable`
  /// return a status with code `.internalError`.
  public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
    errorDelegate?.observe(error)

    let transformed = errorDelegate?.transform(error) ?? error
    let status = (transformed as? GRPCStatusTransformable)?.asGRPCStatus() ?? GRPCStatus.processingError
    self.write(ctx: ctx, data: NIOAny(GRPCServerResponsePart<ResponseMessage>.status(status)), promise: nil)
  }

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      // Head should have been handled by `GRPCChannelHandler`.
      self.errorCaught(ctx: ctx, error: GRPCError.server(.invalidState("unexpected request head received \(requestHead)")))

    case .message(let message):
      do {
        try processMessage(message)
      } catch {
        self.errorCaught(ctx: ctx, error: error)
      }

    case .end:
      endOfStreamReceived()
    }
  }
}

extension BaseCallHandler: ChannelOutboundHandler {
  public typealias OutboundIn = GRPCServerResponsePart<ResponseMessage>
  public typealias OutboundOut = GRPCServerResponsePart<ResponseMessage>

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    guard serverCanWrite else {
      promise?.fail(error: GRPCError.server(.serverNotWritable))
      return
    }

    // We can only write one status; make sure we don't write again.
    if case .status = unwrapOutboundIn(data) {
      serverCanWrite = false
      ctx.writeAndFlush(data, promise: promise)
    } else {
      ctx.write(data, promise: promise)
    }
  }
}
