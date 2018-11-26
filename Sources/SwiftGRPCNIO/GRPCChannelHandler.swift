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
  func handleMethod(_ methodName: String, request: HTTPRequestHead, serverHandler: GRPCChannelHandler, channel: Channel) -> GRPCCallHandler?
}

/// Listens on a newly-opened HTTP2 subchannel and yields to the sub-handler matching a call, if available.
///
/// Once the request headers are available, asks the `CallHandlerProvider` corresponding to the request's service name
/// for an `GRPCCallHandler` object. That object is then forwarded the individual gRPC messages.
public final class GRPCChannelHandler {
  private let servicesByName: [String: CallHandlerProvider]

  public init(servicesByName: [String: CallHandlerProvider]) {
    self.servicesByName = servicesByName
  }
}

extension GRPCChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCServerRequestPart
  public typealias OutboundOut = RawGRPCServerResponsePart
  
  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    let requestPart = self.unwrapInboundIn(data)
    switch requestPart {
    case .head(let requestHead):
      // URI format: "/package.Servicename/MethodName", resulting in the following components separated by a slash:
      // - uriComponents[0]: empty
      // - uriComponents[1]: service name (including the package name);
      //     `CallHandlerProvider`s should provide the service name including the package name.
      // - uriComponents[2]: method name.
      let uriComponents = requestHead.uri.components(separatedBy: "/")
      guard uriComponents.count >= 3 && uriComponents[0].isEmpty,
        let providerForServiceName = servicesByName[uriComponents[1]],
        let callHandler = providerForServiceName.handleMethod(uriComponents[2], request: requestHead, serverHandler: self, channel: ctx.channel) else {
          ctx.writeAndFlush(self.wrapOutboundOut(.status(.unimplemented(method: requestHead.uri))), promise: nil)
          return
      }

      var responseHeaders = HTTPHeaders()
      responseHeaders.add(name: "content-type", value: "application/grpc")
      ctx.write(self.wrapOutboundOut(.headers(responseHeaders)), promise: nil)

      let codec = callHandler.makeGRPCServerCodec()
      ctx.pipeline.add(handler: codec, after: self)
        .then { ctx.pipeline.add(handler: callHandler, after: codec) }
        //! FIXME(lukasa): Fix the ordering of this with NIO 1.12 and replace with `remove(, promise:)`.
        .whenComplete { _ = ctx.pipeline.remove(handler: self) }

    case .message, .end:
      preconditionFailure("received \(requestPart), should have been removed as a handler at this point")
    }
  }
}
