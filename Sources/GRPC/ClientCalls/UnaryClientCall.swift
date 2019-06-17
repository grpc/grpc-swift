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

/// A unary gRPC call. The request is sent on initialization.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `response`: the response from the unary call,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public final class UnaryClientCall<RequestMessage: Message, ResponseMessage: Message>
  : BaseClientCall<RequestMessage, ResponseMessage>,
    UnaryResponseClientCall {
  public let response: EventLoopFuture<ResponseMessage>

  public init(connection: ClientConnection, path: String, request: RequestMessage, callOptions: CallOptions, errorDelegate: ClientErrorDelegate?) {
    let responseHandler = GRPCClientUnaryResponseChannelHandler<ResponseMessage>(
      initialMetadataPromise: connection.channel.eventLoop.makePromise(),
      responsePromise: connection.channel.eventLoop.makePromise(),
      statusPromise: connection.channel.eventLoop.makePromise(),
      errorDelegate: errorDelegate,
      timeout: callOptions.timeout)

    let requestHandler = UnaryRequestChnnelHandler<RequestMessage>(
      requestHead: makeRequestHead(path: path, host: connection.configuration.target.host, callOptions: callOptions),
      request: _Box(request))

    self.response = responseHandler.responsePromise.futureResult
    super.init(
      connection: connection,
      responseHandler: responseHandler,
      requestHandler: requestHandler)
  }
}
