import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Processes individual gRPC messages and stream-close events on a HTTP2 channel.
public protocol GRPCCallHandler: ChannelHandler {
  func makeGRPCServerCodec() -> ChannelHandler
}

// Provides `GRPCCallHandler` objects for the methods on a particular service name.
public protocol CallHandlerProvider {
  var serviceName: String { get }

  func handleMethod(_ methodName: String, headers: HTTPRequestHead, serverHandler: GRPCChannelHandler, channel: Channel) -> GRPCCallHandler?
}

// Listens on a newly-opened HTTP2 channel and waits for the request headers to become available.
// Once those are available, asks the `CallHandlerProvider` corresponding to the request's service name for an
// `GRPCCallHandler` object. That object is then forwarded the individual gRPC messages.
public final class GRPCChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = RawGRPCServerRequestPart

  public typealias OutboundOut = RawGRPCServerResponsePart

  fileprivate let servicesByName: [String: CallHandlerProvider]

  public init(servicesByName: [String: CallHandlerProvider]) {
    self.servicesByName = servicesByName
  }

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    let requestPart = self.unwrapInboundIn(data)
    switch requestPart {
    case .headers(let headers):
      let uriComponents = headers.uri.components(separatedBy: "/")
      guard uriComponents.count >= 3 && uriComponents[0].isEmpty,
        let providerForServiceName = servicesByName[uriComponents[1]],
        let callHandler = providerForServiceName.handleMethod(uriComponents[2], headers: headers, serverHandler: self, channel: ctx.channel) else {
          ctx.writeAndFlush(self.wrapOutboundOut(.status(.unimplemented(method: headers.uri))), promise: nil)
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
