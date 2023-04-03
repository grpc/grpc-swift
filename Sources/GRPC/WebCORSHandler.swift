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
import NIOCore
import NIOHTTP1

/// Handler that manages the CORS protocol for requests incoming from the browser.
internal final class WebCORSHandler {
  let configuration: Server.Configuration.CORS

  private var state: State = .idle
  private enum State: Equatable {
    /// Starting state.
    case idle
    /// CORS preflight request is in progress.
    case processingPreflightRequest
    /// "Real" request is in progress.
    case processingRequest(origin: String?)
  }

  init(configuration: Server.Configuration.CORS) {
    self.configuration = configuration
  }
}

extension WebCORSHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias InboundOut = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case let .head(head):
      self.receivedRequestHead(context: context, head)

    case let .body(body):
      self.receivedRequestBody(context: context, body)

    case let .end(trailers):
      self.receivedRequestEnd(context: context, trailers)
    }
  }

  private func receivedRequestHead(context: ChannelHandlerContext, _ head: HTTPRequestHead) {
    if head.method == .OPTIONS,
       head.headers.contains(.accessControlRequestMethod),
       let origin = head.headers.first(name: "origin") {
      // If the request is OPTIONS with a access-control-request-method header it's a CORS
      // preflight request and is not propagated further.
      self.state = .processingPreflightRequest
      self.handlePreflightRequest(context: context, head: head, origin: origin)
    } else {
      self.state = .processingRequest(origin: head.headers.first(name: "origin"))
      context.fireChannelRead(self.wrapInboundOut(.head(head)))
    }
  }

  private func receivedRequestBody(context: ChannelHandlerContext, _ body: ByteBuffer) {
    // OPTIONS requests do not have a body, but still handle this case to be
    // cautious.
    if self.state == .processingPreflightRequest {
      return
    }

    context.fireChannelRead(self.wrapInboundOut(.body(body)))
  }

  private func receivedRequestEnd(context: ChannelHandlerContext, _ trailers: HTTPHeaders?) {
    if self.state == .processingPreflightRequest {
      // End of OPTIONS request; reset state and finish the response.
      self.state = .idle
      context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    } else {
      context.fireChannelRead(self.wrapInboundOut(.end(trailers)))
    }
  }

  private func handlePreflightRequest(
    context: ChannelHandlerContext,
    head: HTTPRequestHead,
    origin: String
  ) {
    let responseHead: HTTPResponseHead

    if let allowedOrigin = self.configuration.allowedOrigins.header(origin) {
      var headers = HTTPHeaders()
      headers.reserveCapacity(4 + self.configuration.allowedHeaders.count)
      headers.add(name: .accessControlAllowOrigin, value: allowedOrigin)
      headers.add(name: .accessControlAllowMethods, value: "POST")

      for value in self.configuration.allowedHeaders {
        headers.add(name: .accessControlAllowHeaders, value: value)
      }

      if self.configuration.allowCredentialedRequests {
        headers.add(name: .accessControlAllowCredentials, value: "true")
      }

      if self.configuration.preflightCacheExpiration > 0 {
        headers.add(
          name: .accessControlMaxAge,
          value: "\(self.configuration.preflightCacheExpiration)"
        )
      }
      responseHead = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
    } else {
      // Not allowed; respond with 403. This is okay in a pre-flight request.
      responseHead = HTTPResponseHead(version: head.version, status: .forbidden)
    }

    context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
  }
}

extension WebCORSHandler: ChannelOutboundHandler {
  typealias OutboundIn = HTTPServerResponsePart

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let responsePart = self.unwrapOutboundIn(data)
    switch responsePart {
    case var .head(responseHead):
      switch self.state {
      case let .processingRequest(origin):
        self.prepareCORSResponseHead(&responseHead, origin: origin)
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: promise)

      case .idle, .processingPreflightRequest:
        assertionFailure("Writing response head when no request is in progress")
        context.close(promise: nil)
      }

    case .body:
      context.write(data, promise: promise)

    case .end:
      self.state = .idle
      context.write(data, promise: promise)
    }
  }

  private func prepareCORSResponseHead(_ head: inout HTTPResponseHead, origin: String?) {
    guard let header = origin.flatMap({ self.configuration.allowedOrigins.header($0) }) else {
      // No origin or the origin is not allowed; don't treat it as a CORS request.
      return
    }

    head.headers.replaceOrAdd(name: .accessControlAllowOrigin, value: header)

    if self.configuration.allowCredentialedRequests {
      head.headers.add(name: .accessControlAllowCredentials, value: "true")
    }

    //! FIXME: Check whether we can let browsers keep connections alive. It's not possible
    // now as the channel has a state that can't be reused since the pipeline is modified to
    // inject the gRPC call handler.
    head.headers.replaceOrAdd(name: "Connection", value: "close")
  }
}

extension HTTPHeaders {
  fileprivate enum CORSHeader: String {
    case accessControlRequestMethod = "access-control-request-method"
    case accessControlRequestHeaders = "access-control-request-headers"
    case accessControlAllowOrigin = "access-control-allow-origin"
    case accessControlAllowMethods = "access-control-allow-methods"
    case accessControlAllowHeaders = "access-control-allow-headers"
    case accessControlAllowCredentials = "access-control-allow-credentials"
    case accessControlMaxAge = "access-control-max-age"
  }

  fileprivate func contains(_ name: CORSHeader) -> Bool {
    return self.contains(name: name.rawValue)
  }

  fileprivate mutating func add(name: CORSHeader, value: String) {
    self.add(name: name.rawValue, value: value)
  }

  fileprivate mutating func replaceOrAdd(name: CORSHeader, value: String) {
    self.replaceOrAdd(name: name.rawValue, value: value)
  }
}

extension Server.Configuration.CORS.AllowedOrigins {
  internal func header(_ origin: String) -> String? {
    switch self.wrapped {
    case .all:
      return "*"
    case let .only(allowed):
      return allowed.contains(origin) ? origin : nil
    }
  }
}
