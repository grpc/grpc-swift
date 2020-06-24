/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIOHTTP2
import Logging

// This is currently intended for internal testing only.
class EmbeddedGRPCChannel: GRPCChannel {
  let embeddedChannel: EmbeddedChannel
  let multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

  let logger: Logger
  let scheme: String
  let authority: String
  let errorDelegate: ClientErrorDelegate?

  func close() -> EventLoopFuture<Void> {
    return embeddedChannel.close()
  }

  var eventLoop: EventLoop {
    return self.embeddedChannel.eventLoop
  }

  init(errorDelegate: ClientErrorDelegate? = nil) {
    let embeddedChannel = EmbeddedChannel()
    self.embeddedChannel = embeddedChannel
    let logger = Logger(subsystem: .clientChannel)
    self.logger = logger
    self.multiplexer = embeddedChannel.configureGRPCClient(
      errorDelegate: errorDelegate,
      logger: logger
    ).flatMap {
      embeddedChannel.pipeline.handler(type: HTTP2StreamMultiplexer.self)
    }
    self.scheme = "http"
    self.authority = "localhost"
    self.errorDelegate = errorDelegate
  }

  private func makeRequestHead(path: String, options: CallOptions) -> _GRPCRequestHead {
    return _GRPCRequestHead(
      scheme: self.scheme,
      path: path,
      host: self.authority,
      requestID: options.requestIDProvider.requestID(),
      options: options
    )
  }

  internal func makeUnaryCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions
  ) -> UnaryCall<Request, Response> {
    let call = UnaryCall<Request, Response>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      callOptions: callOptions,
      errorDelegate: self.errorDelegate,
      logger: self.logger
    )

    call.send(self.makeRequestHead(path: path, options: callOptions), request: request)

    return call
  }

  internal func makeClientStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions
  ) -> ClientStreamingCall<Request, Response> {
    let call = ClientStreamingCall<Request, Response>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      callOptions: callOptions,
      errorDelegate: self.errorDelegate,
      logger: self.logger
    )

    call.sendHead(self.makeRequestHead(path: path, options: callOptions))

    return call
  }

  internal func makeServerStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    request: Request,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> ServerStreamingCall<Request, Response> {
    let call = ServerStreamingCall<Request, Response>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      callOptions: callOptions,
      errorDelegate: self.errorDelegate,
      logger: self.logger,
      responseHandler: handler
    )

    call.send(self.makeRequestHead(path: path, options: callOptions), request: request)

    return call
  }

  internal func makeBidirectionalStreamingCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    callOptions: CallOptions,
    handler: @escaping (Response) -> Void
  ) -> BidirectionalStreamingCall<Request, Response> {
    let call = BidirectionalStreamingCall<Request, Response>.makeOnHTTP2Stream(
      multiplexer: self.multiplexer,
      callOptions: callOptions,
      errorDelegate: self.errorDelegate,
      logger: self.logger,
      responseHandler: handler
    )

    call.sendHead(self.makeRequestHead(path: path, options: callOptions))

    return call
  }
}
