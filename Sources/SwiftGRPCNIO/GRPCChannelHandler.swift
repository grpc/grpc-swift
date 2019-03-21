import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Processes individual gRPC messages and stream-close events on a HTTP2 channel.
public protocol GRPCCallHandler: ChannelHandler {
  func makeGRPCServerCodec() -> ChannelHandler
}

/// Provides `GRPCCallHandler` objects for the methods on a particular service name.
///
/// Implemented by the generated code.
public protocol CallHandlerProvider: class {
  /// The name of the service this object is providing methods for, including the package path.
  ///
  /// - Example: "io.grpc.Echo.EchoService"
  var serviceName: String { get }

  /// Determines, calls and returns the appropriate request handler (`GRPCCallHandler`), depending on the request's
  /// method. Returns nil for methods not handled by this service.
  func handleMethod(_ methodName: String, request: HTTPRequestHead, serverHandler: GRPCChannelHandler, channel: Channel, errorDelegate: ServerErrorDelegate?) -> GRPCCallHandler?
}

/// Listens on a newly-opened HTTP2 subchannel and yields to the sub-handler matching a call, if available.
///
/// Once the request headers are available, asks the `CallHandlerProvider` corresponding to the request's service name
/// for an `GRPCCallHandler` object. That object is then forwarded the individual gRPC messages.
public final class GRPCChannelHandler {
  private let servicesByName: [String: CallHandlerProvider]
  private weak var errorDelegate: ServerErrorDelegate?

  public init(servicesByName: [String: CallHandlerProvider], errorDelegate: ServerErrorDelegate?) {
    self.servicesByName = servicesByName
    self.errorDelegate = errorDelegate
  }
}

extension GRPCChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCServerRequestPart
  public typealias OutboundOut = RawGRPCServerResponsePart

  public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
    errorDelegate?.observe(error)

    let transformedError = errorDelegate?.transform(error) ?? error
    let status = (transformedError as? GRPCStatusTransformable)?.asGRPCStatus() ?? GRPCStatus.processingError
    ctx.writeAndFlush(wrapOutboundOut(.status(status)), promise: nil)
  }

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    let requestPart = self.unwrapInboundIn(data)
    switch requestPart {
    case .head(let requestHead):
      guard let callHandler = getCallHandler(channel: ctx.channel, requestHead: requestHead) else {
        errorCaught(ctx: ctx, error: GRPCError.server(.unimplementedMethod(requestHead.uri)))
        return
      }

      let codec = callHandler.makeGRPCServerCodec()
      let handlerRemoved: EventLoopPromise<Bool> = ctx.eventLoop.newPromise()
      handlerRemoved.futureResult.whenSuccess { handlerWasRemoved in
        assert(handlerWasRemoved)

        ctx.pipeline.add(handler: callHandler, after: codec).whenComplete {
          // Send the .headers event back to begin the headers flushing for the response.
          // At this point, which headers should be returned is not known, as the content type is
          // processed in HTTP1ToRawGRPCServerCodec. At the same time the HTTP1ToRawGRPCServerCodec
          // handler doesn't have the data to determine whether headers should be returned, as it is
          // this handler that checks whether the stub for the requested Service/Method is implemented.
          // This likely signals that the architecture for these handlers could be improved.
          ctx.writeAndFlush(self.wrapOutboundOut(.headers(HTTPHeaders())), promise: nil)
        }
      }

      ctx.pipeline.add(handler: codec, after: self)
        .whenComplete { ctx.pipeline.remove(handler: self, promise: handlerRemoved) }

    case .message, .end:
      // We can reach this point if we're receiving messages for a method that isn't implemented.
      // A status resposne will have been fired which should also close the stream; there's not a
      // lot we can do at this point.
      break
    }
  }

  private func getCallHandler(channel: Channel, requestHead: HTTPRequestHead) -> GRPCCallHandler? {
    // URI format: "/package.Servicename/MethodName", resulting in the following components separated by a slash:
    // - uriComponents[0]: empty
    // - uriComponents[1]: service name (including the package name);
    //     `CallHandlerProvider`s should provide the service name including the package name.
    // - uriComponents[2]: method name.
    let uriComponents = requestHead.uri.components(separatedBy: "/")
    guard uriComponents.count >= 3 && uriComponents[0].isEmpty,
      let providerForServiceName = servicesByName[uriComponents[1]],
      let callHandler = providerForServiceName.handleMethod(uriComponents[2], request: requestHead, serverHandler: self, channel: channel, errorDelegate: errorDelegate) else {
        return nil
    }
    return callHandler
  }
}
