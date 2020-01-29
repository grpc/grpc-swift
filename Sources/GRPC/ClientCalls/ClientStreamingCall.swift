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
import Logging

/// A client-streaming gRPC call.
///
/// Messages should be sent via the `send` method; an `.end` message should be sent
/// to indicate the final message has been sent.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `response`: the response from the call,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public final class ClientStreamingCall<RequestPayload: GRPCPayload, ResponsePayload: GRPCPayload>
  : BaseClientCall<RequestPayload, ResponsePayload>,
    StreamingRequestClientCall,
    UnaryResponseClientCall {
  public let response: EventLoopFuture<ResponsePayload>
  private var messageQueue: EventLoopFuture<Void>

  public init(
    connection: ClientConnection,
    path: String,
    callOptions: CallOptions,
    errorDelegate: ClientErrorDelegate?
  ) {
    let requestID = callOptions.requestIDProvider.requestID()
    let logger = Logger(subsystem: .clientChannelCall, metadata: [MetadataKey.requestID: "\(requestID)"])
    logger.debug("starting rpc", metadata: ["path": "\(path)"])

    self.messageQueue = connection.eventLoop.makeSucceededFuture(())
    let responsePromise = connection.eventLoop.makePromise(of: ResponsePayload.self)
    self.response = responsePromise.futureResult

    let responseHandler = GRPCClientUnaryResponseChannelHandler(
      initialMetadataPromise: connection.channel.eventLoop.makePromise(),
      trailingMetadataPromise: connection.channel.eventLoop.makePromise(),
      responsePromise: responsePromise,
      statusPromise: connection.channel.eventLoop.makePromise(),
      errorDelegate: errorDelegate,
      timeout: callOptions.timeout,
      logger: logger
    )

    let requestHead = _GRPCRequestHead(
      scheme: connection.configuration.httpProtocol.scheme,
      path: path,
      host: connection.configuration.target.host,
      requestID: requestID,
      encoding: connection.configuration.messageEncoding,
      options: callOptions
    )

    let requestHandler = _StreamingRequestChannelHandler<RequestPayload>(requestHead: requestHead)

    super.init(
      eventLoop: connection.eventLoop,
      multiplexer: connection.multiplexer,
      callType: .clientStreaming,
      responseHandler: responseHandler,
      requestHandler: requestHandler,
      logger: logger
    )
  }

  public func newMessageQueue() -> EventLoopFuture<Void> {
    return self.messageQueue
  }
}
