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

/// A bidirectional-streaming gRPC call. Each response is passed to the provided observer block.
///
/// Messages should be sent via the `send` method; an `.end` message should be sent
/// to indicate the final message has been sent.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public final class BidirectionalStreamingClientCall<RequestMessage: Message, ResponseMessage: Message>
  : BaseClientCall<RequestMessage, ResponseMessage>,
    StreamingRequestClientCall {
  private var messageQueue: EventLoopFuture<Void>

  public init(connection: GRPCClientConnection, path: String, callOptions: CallOptions, errorDelegate: ClientErrorDelegate?, handler: @escaping (ResponseMessage) -> Void) {
    self.messageQueue = connection.channel.eventLoop.makeSucceededFuture(())

    let responseHandler = GRPCClientStreamingResponseChannelHandler(
      initialMetadataPromise: connection.channel.eventLoop.makePromise(),
      statusPromise: connection.channel.eventLoop.makePromise(),
      errorDelegate: errorDelegate,
      timeout: callOptions.timeout,
      responseHandler: handler)

    let requestHandler = GRPCClientStreamingRequestChannelHandler<RequestMessage>(
      requestHead: makeRequestHead(path: path, host: connection.configuration.target.host, callOptions: callOptions))

    super.init(
      connection: connection,
      responseHandler: responseHandler,
      requestHandler: requestHandler)
  }

  public func newMessageQueue() -> EventLoopFuture<Void> {
    return self.messageQueue
  }
}
