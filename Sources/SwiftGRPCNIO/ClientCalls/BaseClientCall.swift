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

public class BaseClientCall<RequestMessage: Message, ResponseMessage: Message>: ClientCall {
  private let subchannelPromise: EventLoopPromise<Channel>
  private let initialMetadataPromise: EventLoopPromise<HTTPHeaders>
  private let statusPromise: EventLoopPromise<GRPCStatus>

  public var subchannel: EventLoopFuture<Channel> { return subchannelPromise.futureResult }
  public var initialMetadata: EventLoopFuture<HTTPHeaders> { return initialMetadataPromise.futureResult }
  public var status: EventLoopFuture<GRPCStatus> { return statusPromise.futureResult }

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
    self.subchannelPromise = channel.eventLoop.newPromise()
    self.initialMetadataPromise = channel.eventLoop.newPromise()
    self.statusPromise = channel.eventLoop.newPromise()

    let channelHandler = GRPCClientResponseChannelHandler<ResponseMessage>(metadata: self.initialMetadataPromise,
                                                                           status: self.statusPromise,
                                                                           messageHandler: responseHandler)

    /// Create a new HTTP2 stream to handle calls.
    channel.eventLoop.execute {
      multiplexer.createStreamChannel(promise: self.subchannelPromise) { (subchannel, streamID) -> EventLoopFuture<Void> in
        subchannel.pipeline.addHandlers([HTTP2ToHTTP1ClientCodec(streamID: streamID, httpProtocol: .http),
                                         HTTP1ToRawGRPCClientCodec(),
                                         GRPCClientCodec<RequestMessage, ResponseMessage>(),
                                         channelHandler],
                                        first: false)
      }
    }
  }

  internal func send(requestHead: HTTPRequestHead, request: RequestMessage? = nil) {
    subchannel.whenSuccess { channel in
      channel.write(GRPCClientRequestPart<RequestMessage>.head(requestHead), promise: nil)
      if let request = request {
        channel.write(GRPCClientRequestPart<RequestMessage>.message(request), promise: nil)
        channel.writeAndFlush(GRPCClientRequestPart<RequestMessage>.end, promise: nil)
      }
    }
  }

  internal func setTimeout(_ timeout: GRPCTimeout?) {
    guard let timeout = timeout else { return }

    self.subchannel.whenSuccess { channel in
      let timeoutPromise = channel.eventLoop.newPromise(of: Void.self)

      timeoutPromise.futureResult.whenFailure {
        self.failPromises(error: $0)
      }

      channel.eventLoop.scheduleTask(in: timeout.asNIOTimeAmount) {
        timeoutPromise.fail(error: GRPCStatus(code: .deadlineExceeded))
      }
    }
  }

  internal func makeRequestHead(path: String, host: String, callOptions: CallOptions) -> HTTPRequestHead {
    var requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: path)

    callOptions.customMetadata.forEach { name, value in
      requestHead.headers.add(name: name, value: value)
    }

    requestHead.headers.add(name: "host", value: host)
    requestHead.headers.add(name: "content-type", value: "application/grpc")
    requestHead.headers.add(name: "te", value: "trailers")
    requestHead.headers.add(name: "user-agent", value: "grpc-swift-nio")

    let acceptedEncoding = CompressionMechanism.acceptEncoding
      .map { $0.rawValue }
      .joined(separator: ",")

    requestHead.headers.add(name: "grpc-accept-encoding", value: acceptedEncoding)

    if let timeout = callOptions.timeout {
      requestHead.headers.add(name: "grpc-timeout", value: String(describing: timeout))
    }

    return requestHead
  }

  internal func failPromises(error: Error) {
    self.statusPromise.fail(error: error)
    self.initialMetadataPromise.fail(error: error)
  }

  public func cancel() {
    self.subchannel.whenSuccess { channel in
      channel.close(mode: .all, promise: nil)
    }
    self.failPromises(error: GRPCStatus.cancelled)
  }
}
