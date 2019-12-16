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
import NIO
import NIOHPACK
import NIOHTTP2
import SwiftProtobuf
import Logging

/// This class provides much of the boilerplate for the four types of gRPC call objects returned to
/// framework users.
///
/// Each call will be configured on a multiplexed channel on the given connection. The multiplexed
/// channel will be configured as such:
///
///              ┌──────────────────────────────┐
///              │ ClientResponseChannelHandler │
///              └────────────▲─────────────────┘
///                           │      ┌─────────────────────────────┐
///                           │      │ ClientRequestChannelHandler │
///                           │      └────────────────┬────────────┘
/// GRPCClientResponsePart<T1>│                       │GRPCClientRequestPart<T2>
///                         ┌─┴───────────────────────▼─┐
///                         │ GRPCClientChannelHandler  │
///                         └─▲───────────────────────┬─┘
///                 HTTP2Frame│                       │HTTP2Frame
///                           |                       |
///
/// Note: the "main" pipeline provided by the channel in `ClientConnection`.
///
/// Setup includes:
/// - creation of an HTTP/2 stream for the call to execute on,
/// - configuration of the NIO channel handlers for the stream, and
/// - setting a call timeout, if one is provided.
///
/// This class also provides much of the framework user facing functionality via conformance to
/// `ClientCall`.
public class BaseClientCall<Request: Message, Response: Message>: ClientCall {
  public typealias RequestMessage = Request
  public typealias ResponseMessage = Response

  internal let logger: Logger

  /// HTTP/2 multiplexer providing the stream.
  internal let multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>

  // Note: documentation is inherited from the `ClientCall` protocol.
  public let subchannel: EventLoopFuture<Channel>
  public let initialMetadata: EventLoopFuture<HPACKHeaders>
  public let trailingMetadata: EventLoopFuture<HPACKHeaders>
  public let status: EventLoopFuture<GRPCStatus>

  /// Sets up a new RPC call.
  ///
  /// - Parameter eventLoop: The event loop the connection is running on.
  /// - Parameter multiplexer: The multiplexer future to use to provide a stream channel.
  /// - Parameter callType: The type of RPC call, e.g. unary, server-streaming.
  /// - Parameter responseHandler: Channel handler for reading responses.
  /// - Parameter requestHandler: Channel handler for writing requests..
  /// - Parameter logger: Logger.
  init(
    eventLoop: EventLoop,
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    callType: GRPCCallType,
    responseHandler: GRPCClientResponseChannelHandler<Response>,
    requestHandler: _ClientRequestChannelHandler<Request>,
    logger: Logger
  ) {
    self.logger = logger
    self.multiplexer = multiplexer

    let streamPromise = eventLoop.makePromise(of: Channel.self)

    // Take the futures we need from the response handler.
    self.subchannel = streamPromise.futureResult
    self.initialMetadata = responseHandler.initialMetadataPromise.futureResult
    self.trailingMetadata = responseHandler.trailingMetadataPromise.futureResult
    self.status = responseHandler.statusPromise.futureResult

    // If the stream (or multiplexer) fail we need to fail any responses.
    self.multiplexer.cascadeFailure(to: streamPromise)
    streamPromise.futureResult.whenFailure(responseHandler.onError)

    // Create an HTTP/2 stream and configure it with the gRPC handler.
    self.multiplexer.whenSuccess { multiplexer in
      multiplexer.createStreamChannel(promise: streamPromise) { (stream, streamID) -> EventLoopFuture<Void> in
        stream.pipeline.addHandlers([
          _GRPCClientChannelHandler<Request, Response>(streamID: streamID, callType: callType, logger: logger),
          responseHandler,
          requestHandler
        ])
      }
    }

    // Schedule the timeout.
    responseHandler.scheduleTimeout(eventLoop: eventLoop)
  }

  public func cancel(promise: EventLoopPromise<Void>?) {
    self.subchannel.whenComplete {
      switch $0 {
      case .success(let channel):
        self.logger.trace("firing .cancelled event")
        channel.pipeline.triggerUserOutboundEvent(GRPCClientUserEvent.cancelled, promise: promise)
      case .failure(let error):
        promise?.fail(error)
      }
    }
  }

  public func cancel() -> EventLoopFuture<Void> {
    return self.subchannel.flatMap { channel in
      self.logger.trace("firing .cancelled event")
      return channel.pipeline.triggerUserOutboundEvent(GRPCClientUserEvent.cancelled)
    }
  }
}

extension GRPCRequestHead {
  init(
    scheme: String,
    path: String,
    host: String,
    requestID: String,
    options: CallOptions
  ) {
    var customMetadata = options.customMetadata
    if let requestIDHeader = options.requestIDHeader {
      customMetadata.add(name: requestIDHeader, value: requestID)
    }

    self = GRPCRequestHead(
      method: options.cacheable ? "GET" : "POST",
      scheme: scheme,
      path: path,
      host: host,
      timeout: options.timeout,
      customMetadata: customMetadata
    )
  }
}
