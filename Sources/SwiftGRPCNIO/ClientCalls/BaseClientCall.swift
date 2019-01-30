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

public protocol ClientCall {
  associatedtype RequestMessage: Message
  associatedtype ResponseMessage: Message

  /// HTTP2 stream that requests and responses are sent and received on.
  var subchannel: EventLoopFuture<Channel> { get }

  /// Initial response metadata.
  var initialMetadata: EventLoopFuture<HTTPHeaders> { get }

  /// Response status.
  var status: EventLoopFuture<GRPCStatus> { get }

  /// Trailing response metadata.
  ///
  /// This is the same metadata as `GRPCStatus.trailingMetadata` returned by `status`.
  var trailingMetadata: EventLoopFuture<HTTPHeaders> { get }
}


extension ClientCall {
  public var trailingMetadata: EventLoopFuture<HTTPHeaders> {
    return status.map { $0.trailingMetadata }
  }
}


public protocol StreamingRequestClientCall: ClientCall {
  func send(_ event: StreamEvent<RequestMessage>)
}


extension StreamingRequestClientCall {
  /// Sends a request to the service. Callers must terminate the stream of messages
  /// with an `.end` event.
  ///
  /// - Parameter event: event to send.
  public func send(_ event: StreamEvent<RequestMessage>) {
    let request: GRPCClientRequestPart<RequestMessage>
    switch event {
    case .message(let message):
      request = .message(message)

    case .end:
      request = .end
    }

    subchannel.whenSuccess { $0.write(NIOAny(request), promise: nil) }
  }
}


public protocol UnaryResponseClientCall: ClientCall {
  var response: EventLoopFuture<ResponseMessage> { get }
}


public class BaseClientCall<RequestMessage: Message, ResponseMessage: Message>: ClientCall {
  public let subchannel: EventLoopFuture<Channel>
  public let initialMetadata: EventLoopFuture<HTTPHeaders>
  public let status: EventLoopFuture<GRPCStatus>

  /// Sets up a gRPC call.
  ///
  /// Creates a new HTTP2 stream (`subchannel`) using the given multiplexer and configures the pipeline to
  /// handle client gRPC requests and responses.
  ///
  /// - Parameters:
  ///   - channel: the main channel.
  ///   - multiplexer: HTTP2 stream multiplexer on which HTTP2 streams are created.
  ///   - responseHandler: handler for received messages.
  init(
    channel: Channel,
    multiplexer: HTTP2StreamMultiplexer,
    responseHandler: GRPCClientResponseChannelHandler<ResponseMessage>.ResponseMessageHandler
  ) {
    let subchannelPromise: EventLoopPromise<Channel> = channel.eventLoop.newPromise()
    let metadataPromise: EventLoopPromise<HTTPHeaders> = channel.eventLoop.newPromise()
    let statusPromise: EventLoopPromise<GRPCStatus> = channel.eventLoop.newPromise()

    let channelHandler = GRPCClientResponseChannelHandler<ResponseMessage>(metadata: metadataPromise, status: statusPromise, messageHandler: responseHandler)

    /// Create a new HTTP2 stream to handle calls.
    channel.eventLoop.execute {
      multiplexer.createStreamChannel(promise: subchannelPromise) { (subchannel, streamID) -> EventLoopFuture<Void> in
        subchannel.pipeline.addHandlers([HTTP2ToHTTP1ClientCodec(streamID: streamID, httpProtocol: .http),
                                         HTTP1ToRawGRPCClientCodec(),
                                         GRPCClientCodec<RequestMessage, ResponseMessage>(),
                                         channelHandler],
                                        first: false)
      }
    }

    self.subchannel = subchannelPromise.futureResult
    self.initialMetadata = metadataPromise.futureResult
    self.status = statusPromise.futureResult
  }

  internal func makeRequestHead(path: String, host: String, customMetadata: HTTPHeaders? = nil) -> HTTPRequestHead {
    var requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: path)
    customMetadata?.forEach { name, value in
      requestHead.headers.add(name: name, value: value)
    }

    requestHead.headers.add(name: "host", value: host)
    requestHead.headers.add(name: "content-type", value: "application/grpc")
    requestHead.headers.add(name: "te", value: "trailers")
    requestHead.headers.add(name: "user-agent", value: "grpc-swift-nio")
    return requestHead
  }
}
