import NIO
import NIOHTTP1

/// Handler that manages the CORS protocol for requests incoming from the browser.
public class WebCORSHandler {
  var requestMethod: HTTPMethod?
}

extension WebCORSHandler: ChannelInboundHandler {
  public typealias InboundIn = HTTPServerRequestPart
  public typealias OutboundOut = HTTPServerResponsePart

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    // If the request is OPTIONS, the request is not propagated further.
    switch self.unwrapInboundIn(data) {
    case .head(let requestHead):
      requestMethod = requestHead.method
      if requestMethod == .OPTIONS {
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "POST")
        headers.add(name: "Access-Control-Allow-Headers",
                    value: "content-type,x-grpc-web,x-user-agent")
        headers.add(name: "Access-Control-Max-Age", value: "86400")
        ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: requestHead.version,
                                                              status: .ok,
                                                              headers: headers))),
                  promise: nil)
        return
      }
    case .body:
      if requestMethod == .OPTIONS {
        // OPTIONS requests do not have a body, but still handle this case to be
        // cautious.
        return
      }

    case .end:
      if requestMethod == .OPTIONS {
        ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        requestMethod = nil
        return
      }
    }
    // The OPTIONS request should be fully handled at this point.
    ctx.fireChannelRead(data)
  }
}

extension WebCORSHandler: ChannelOutboundHandler {
  public typealias OutboundIn = HTTPServerResponsePart

  public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case .head(let responseHead):
      var headers = responseHead.headers
      // CORS requires all requests to have an Allow-Origin header.
      headers.add(name: "Access-Control-Allow-Origin", value: "*")
      //! FIXME: Check whether we can let browsers keep connections alive. It's not possible
      // now as the channel has a state that can't be reused since the pipeline is modified to
      // inject the gRPC call handler.
      headers.add(name: "Connection", value: "close")

      ctx.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: responseHead.version,
                                                            status: responseHead.status,
                                                            headers: headers))),
                promise: promise)
    default:
      ctx.write(data, promise: promise)
    }
  }
}
