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
import NIOCore
import NIOEmbedded
import SwiftProtobuf

extension EmbeddedChannel {
  /// Configures an `EmbeddedChannel` for the `EmbeddedClientThroughput` benchmark.
  ///
  /// - Important: This is **not** part of the public API.
  public func _configureForEmbeddedThroughputTest<Request: Message, Response: Message>(
    callType: GRPCCallType,
    logger: Logger,
    requestType: Request.Type = Request.self,
    responseType: Response.Type = Response.self
  ) -> EventLoopFuture<Void> {
    return self.pipeline.addHandlers([
      GRPCClientChannelHandler(
        callType: callType,
        maximumReceiveMessageLength: .max,
        logger: logger
      ),
      GRPCClientCodecHandler(
        serializer: ProtobufSerializer<Request>(),
        deserializer: ProtobufDeserializer<Response>()
      ),
    ])
  }

  public func _configureForEmbeddedServerTest(
    servicesByName serviceProviders: [Substring: CallHandlerProvider],
    encoding: ServerMessageEncoding,
    normalizeHeaders: Bool,
    logger: Logger
  ) -> EventLoopFuture<Void> {
    let codec = HTTP2ToRawGRPCServerCodec(
      servicesByName: serviceProviders,
      encoding: encoding,
      errorDelegate: nil,
      normalizeHeaders: normalizeHeaders,
      maximumReceiveMessageLength: .max,
      logger: logger
    )
    return self.pipeline.addHandler(codec)
  }

  public func _configureForServerFuzzing(configuration: Server.Configuration) throws {
    let configurator = GRPCServerPipelineConfigurator(configuration: configuration)
    // We're always on an `EmbeddedEventLoop`, this is fine.
    try self.pipeline.syncOperations.addHandler(configurator)
  }
}
