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
import NIOHPACK
import Logging

/// A unary gRPC call. The request is sent on initialization.
public final class UnaryCall<
  RequestPayload: GRPCPayload,
  ResponsePayload: GRPCPayload
>: UnaryResponseClientCall {
  private let transport: ChannelTransport<RequestPayload, ResponsePayload>

  /// The options used to make the RPC.
  public let options: CallOptions

  /// The `Channel` used to transport messages for this RPC.
  public var subchannel: EventLoopFuture<Channel> {
    return self.transport.streamChannel()
  }

  /// The `EventLoop` this call is running on.
  public var eventLoop: EventLoop {
    return self.transport.eventLoop
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel(promise: EventLoopPromise<Void>?) {
    self.transport.cancel(promise: promise)
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public let initialMetadata: EventLoopFuture<HPACKHeaders>

  /// The response returned by the server.
  public let response: EventLoopFuture<ResponsePayload>

  /// The trailing metadata returned from the server.
  public let trailingMetadata: EventLoopFuture<HPACKHeaders>

  /// The final status of the the RPC.
  public let status: EventLoopFuture<GRPCStatus>


  internal init(
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
    logger[metadataKey: "path"] = "\(path)"

    let responsePromise: EventLoopPromise<ResponsePayload> = eventLoop.makePromise()
    self.transport = ChannelTransport(
      multiplexer: multiplexer,
      responseContainer: .init(eventLoop: eventLoop, unaryResponsePromise: responsePromise),
      callType: .unary,
      timeout: callOptions.timeout,
      errorDelegate: errorDelegate,
      logger: logger
    )

    self.options = callOptions
    self.initialMetadata = self.transport.responseContainer.initialMetadata
    self.trailingMetadata = self.transport.responseContainer.trailingMetadata
    self.response = responsePromise.futureResult
    self.status = self.transport.responseContainer.status

    let requestHead = _GRPCRequestHead(
      scheme: scheme,
      path: path,
      host: authority,
      requestID: requestID,
      options: callOptions
    )

    self.transport.sendUnary(
      requestHead,
      request: request,
      compressed: callOptions.messageEncoding.enabledForRequests
    )
  }
}
