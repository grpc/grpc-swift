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
import NIOHTTP1
import NIOHTTP2
import SwiftProtobuf
import Logging

/// This class provides much of the boilerplate for the four types of gRPC call objects returned to framework
/// users.
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
///                         │       GRPCClientCodec     │
///                         └─▲───────────────────────┬─┘
///  RawGRPCClientResponsePart│                       │RawGRPCClientRequestPart
///                         ┌─┴───────────────────────▼─┐
///                         │ HTTP1ToRawGRPCClientCodec │
///                         └─▲───────────────────────┬─┘
///     HTTPClientResponsePart│                       │HTTPClientRequestPart
///                         ┌─┴───────────────────────▼─┐
///                         │  HTTP2ToHTTP1ClientCodec  │
///                         └─▲───────────────────────┬─┘
///                 HTTP2Frame│                       │HTTP2Frame
///                           |                       |
///
/// Note: below the `HTTP2ToHTTP1ClientCodec` is the "main" pipeline provided by the channel in
/// `ClientConnection`.
///
/// Setup includes:
/// - creation of an HTTP/2 stream for the call to execute on,
/// - configuration of the NIO channel handlers for the stream, and
/// - setting a call timeout, if one is provided.
///
/// This class also provides much of the framework user facing functionality via conformance to `ClientCall`.
open class BaseClientCall<RequestMessage: Message, ResponseMessage: Message> {
  internal let logger: Logger

  /// The underlying `ClientConnection` providing the HTTP/2 channel and multiplexer.
  internal let connection: ClientConnection

  /// Promise for an HTTP/2 stream to execute the call on.
  internal let streamPromise: EventLoopPromise<Channel>

  /// Channel handler for responses.
  internal let responseHandler: ClientResponseChannelHandler<ResponseMessage>

  /// Channel handler for requests.
  internal let requestHandler: ClientRequestChannelHandler<RequestMessage>

  // Note: documentation is inherited from the `ClientCall` protocol.
  public let subchannel: EventLoopFuture<Channel>
  public let initialMetadata: EventLoopFuture<HTTPHeaders>
  public let status: EventLoopFuture<GRPCStatus>

  /// Sets up a gRPC call.
  ///
  /// This involves creating a new HTTP/2 stream on the multiplexer provided by `connection`. The
  /// channel associated with the stream is configured to use the provided request and response
  /// handlers. Note that the request head will be sent automatically from the request handler when
  /// the channel becomes active.
  ///
  /// - Parameters:
  ///   - connection: connection containing the HTTP/2 channel and multiplexer to use for this call.
  ///   - responseHandler: a channel handler for receiving responses.
  ///   - requestHandler: a channel handler for sending requests.
  init(
    connection: ClientConnection,
    responseHandler: ClientResponseChannelHandler<ResponseMessage>,
    requestHandler: ClientRequestChannelHandler<RequestMessage>,
    logger: Logger
  ) {
    self.logger = logger

    self.connection = connection
    self.responseHandler = responseHandler
    self.requestHandler = requestHandler
    self.streamPromise = connection.channel.eventLoop.makePromise()

    self.subchannel = self.streamPromise.futureResult
    self.initialMetadata = self.responseHandler.initialMetadataPromise.futureResult
    self.status = self.responseHandler.statusPromise.futureResult

    self.streamPromise.futureResult.whenFailure { error in
      self.logger.error("failed to create http/2 stream", metadata: [MetadataKey.error: "\(error)"])
      self.responseHandler.observeError(.unknown(error, origin: .client))
    }

    self.createStreamChannel()
    self.responseHandler.scheduleTimeout(eventLoop: connection.eventLoop)
  }

  /// Creates and configures an HTTP/2 stream channel. The `self.subchannel` future will hold the
  /// stream channel once it has been created.
  private func createStreamChannel() {
    self.connection.multiplexer.whenFailure { error in
      self.logger.error("failed to get http/2 multiplexer", metadata: [MetadataKey.error: "\(error)"])
      self.streamPromise.fail(error)
    }

    self.connection.multiplexer.whenSuccess { multiplexer in
      multiplexer.createStreamChannel(promise: self.streamPromise) { (subchannel, streamID) -> EventLoopFuture<Void> in
        subchannel.pipeline.addHandlers(
          HTTP2ToHTTP1ClientCodec(streamID: streamID, httpProtocol: self.connection.configuration.httpProtocol),
          HTTP1ToRawGRPCClientCodec(logger: self.logger),
          GRPCClientCodec<RequestMessage, ResponseMessage>(logger: self.logger),
          self.requestHandler,
          self.responseHandler)
      }
    }
  }
}

extension BaseClientCall: ClientCall {
  // Workaround for: https://bugs.swift.org/browse/SR-10128
  // Once resolved this can become a default implementation on `ClientCall`.
  public var trailingMetadata: EventLoopFuture<HTTPHeaders> {
    return status.map { $0.trailingMetadata }
  }

  public func cancel() {
    self.logger.info("cancelling call")
    self.connection.channel.eventLoop.execute {
      self.subchannel.whenComplete { result in
        switch result {
        case .success(let channel):
          self.logger.debug("firing .cancelled event")
          channel.pipeline.fireUserInboundEventTriggered(GRPCClientUserEvent.cancelled)

        case .failure(let error):
          self.logger.debug(
            "cancelling call will no-op because no http/2 stream creation",
            metadata: [MetadataKey.error: "\(error)"]
          )
        }
      }
    }
  }
}

/// Makes a request head.
///
/// - Parameter path: The path of the gRPC call, e.g. "/serviceName/methodName".
/// - Parameter host: The host serving the call.
/// - Parameter callOptions: Options used when making this call.
/// - Parameter requestID: The request ID used for this call. If `callOptions` specifies a
///   non-nil `reqeuestIDHeader` then this request ID will be added to the headers with the
///   specified header name.
internal func makeRequestHead(path: String, host: String, callOptions: CallOptions, requestID: String) -> HTTPRequestHead {
  var headers: HTTPHeaders = [
    "content-type": "application/grpc",
    // Used to detect incompatible proxies, as per https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
    "te": "trailers",
    //! FIXME: Add a more specific user-agent, see: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#user-agents
    "user-agent": "grpc-swift-nio",
    // We're dealing with HTTP/1; the NIO HTTP2ToHTTP1Codec replaces "host" with ":authority".
    "host": host,
    GRPCHeaderName.acceptEncoding: CompressionMechanism.acceptEncodingHeader,
  ]

  if callOptions.timeout != .infinite {
    headers.add(name: GRPCHeaderName.timeout, value: String(describing: callOptions.timeout))
  }

  headers.add(contentsOf: callOptions.customMetadata)

  if let headerName = callOptions.requestIDHeader {
    headers.add(name: headerName, value: requestID)
  }

  let method: HTTPMethod = callOptions.cacheable ? .GET : .POST
  return HTTPRequestHead(version: .init(major: 2, minor: 0), method: method, uri: path, headers: headers)
}
