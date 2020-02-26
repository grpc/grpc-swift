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
import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1
import NIOHTTP2
import Logging

/// A unary gRPC call. The request is sent on initialization.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `response`: the response from the unary call,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public final class UnaryCall<RequestPayload: GRPCPayload, ResponsePayload: GRPCPayload>
  : BaseClientCall<RequestPayload, ResponsePayload>,
    UnaryResponseClientCall {
  public let response: EventLoopFuture<ResponsePayload>

  init(
    path: String,
    scheme: String,
    authority: String,
    callOptions: CallOptions,
    eventLoop: EventLoop,
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger,
    request: RequestPayload
  ) {
    let requestID = callOptions.requestIDProvider.requestID()
    var logger = logger
    logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
    logger.debug("starting rpc", metadata: ["path": "\(path)"])

    let responsePromise = eventLoop.makePromise(of: ResponsePayload.self)
    self.response = responsePromise.futureResult

    let responseHandler = GRPCClientUnaryResponseChannelHandler<ResponsePayload>(
      initialMetadataPromise: eventLoop.makePromise(),
      trailingMetadataPromise: eventLoop.makePromise(),
      responsePromise: responsePromise,
      statusPromise: eventLoop.makePromise(),
      errorDelegate: errorDelegate,
      timeout: callOptions.timeout,
      logger: logger
    )

    let requestHead = _GRPCRequestHead(
      scheme: scheme,
      path: path,
      host: authority,
      requestID: requestID,
      options: callOptions
    )

    let requestHandler = _UnaryRequestChannelHandler<RequestPayload>(
      requestHead: requestHead,
      request: .init(request, compressed: callOptions.messageEncoding.enabledForRequests)
    )

    super.init(
      eventLoop: eventLoop,
      multiplexer: multiplexer,
      callType: .unary,
      callOptions: callOptions,
      responseHandler: responseHandler,
      requestHandler: requestHandler,
      logger: logger
    )
  }
}
