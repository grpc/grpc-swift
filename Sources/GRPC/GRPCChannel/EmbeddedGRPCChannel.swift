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
import Logging
import NIO
import NIOHTTP2
import SwiftProtobuf

// This is currently intended for internal testing only.
class EmbeddedGRPCChannel: GRPCChannel {
  let embeddedChannel: EmbeddedChannel
  let multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

  let logger: Logger
  let scheme: String
  let authority: String
  let errorDelegate: ClientErrorDelegate?

  func close() -> EventLoopFuture<Void> {
    return self.embeddedChannel.close()
  }

  var eventLoop: EventLoop {
    return self.embeddedChannel.eventLoop
  }

  init(
    logger: Logger = Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() }),
    errorDelegate: ClientErrorDelegate? = nil
  ) {
    let embeddedChannel = EmbeddedChannel()
    self.embeddedChannel = embeddedChannel
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

  internal func makeCall<Request: Message, Response: Message>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return Call(
      path: path,
      type: type,
      eventLoop: self.eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        multiplexer: self.multiplexer,
        authority: self.authority,
        scheme: self.scheme,
        // This is internal and only for testing, so max is fine here.
        maximumReceiveMessageLength: .max,
        errorDelegate: self.errorDelegate
      )
    )
  }

  internal func makeCall<Request: GRPCPayload, Response: GRPCPayload>(
    path: String,
    type: GRPCCallType,
    callOptions: CallOptions,
    interceptors: [ClientInterceptor<Request, Response>]
  ) -> Call<Request, Response> {
    return Call(
      path: path,
      type: type,
      eventLoop: self.eventLoop,
      options: callOptions,
      interceptors: interceptors,
      transportFactory: .http2(
        multiplexer: self.multiplexer,
        authority: self.authority,
        scheme: self.scheme,
        // This is internal and only for testing, so max is fine here.
        maximumReceiveMessageLength: .max,
        errorDelegate: self.errorDelegate
      )
    )
  }
}
