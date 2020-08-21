/*
 * Copyright 2019, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import NIO
import NIOHTTP1

/// Handler that manages the CORS protocol for requests incoming from the browser.
internal class WebCORSHandler {
  var requestMethod: HTTPMethod?
}

extension WebCORSHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    // If the request is OPTIONS, the request is not propagated further.
    switch self.unwrapInboundIn(data) {
    case let .head(requestHead):
      self.requestMethod = requestHead.method
      if self.requestMethod == .OPTIONS {
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "POST")
        headers.add(
          name: "Access-Control-Allow-Headers",
          value: "content-type,x-grpc-web,x-user-agent"
        )
        headers.add(name: "Access-Control-Max-Age", value: "86400")
        context.write(
          self.wrapOutboundOut(.head(HTTPResponseHead(
            version: requestHead.version,
            status: .ok,
            headers: headers
          ))),
          promise: nil
        )
        return
      }
    case .body:
      if self.requestMethod == .OPTIONS {
        // OPTIONS requests do not have a body, but still handle this case to be
        // cautious.
        return
      }

    case .end:
      if self.requestMethod == .OPTIONS {
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        self.requestMethod = nil
        return
      }
    }
    // The OPTIONS request should be fully handled at this point.
    context.fireChannelRead(data)
  }
}

extension WebCORSHandler: ChannelOutboundHandler {
  typealias OutboundIn = HTTPServerResponsePart

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case let .head(responseHead):
      var headers = responseHead.headers
      // CORS requires all requests to have an Allow-Origin header.
      headers.add(name: "Access-Control-Allow-Origin", value: "*")
      //! FIXME: Check whether we can let browsers keep connections alive. It's not possible
      // now as the channel has a state that can't be reused since the pipeline is modified to
      // inject the gRPC call handler.
      headers.add(name: "Connection", value: "close")

      context.write(
        self.wrapOutboundOut(.head(HTTPResponseHead(
          version: responseHead.version,
          status: responseHead.status,
          headers: headers
        ))),
        promise: promise
      )
    default:
      context.write(data, promise: promise)
    }
  }
}
