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

public class BaseClientCall<RequestMessage: Message, ResponseMessage: Message> {
  /// The underlying `GRPCClient` providing the HTTP/2 channel and multiplexer.
  internal let client: GRPCClient

  /// Promise for an HTTP/2 stream.
  internal let streamPromise: EventLoopPromise<Channel>

  /// Client channel handler. Handles some internal state for reading/writing messages to the channel.
  /// The handler also owns the promises for the futures that this class surfaces to the user (such as
  /// `initialMetadata` and `status`).
  internal let clientChannelHandler: GRPCClientChannelHandler<RequestMessage, ResponseMessage>

  /// Sets up a gRPC call.
  ///
  /// A number of actions are performed:
  /// - a new HTTP/2 stream is created and configured using channel and multiplexer provided by `client`,
  /// - a callback is registered on the new stream (`subchannel`) to send the request head,
  /// - a timeout is scheduled if one is set in the `callOptions`.
  ///
  /// - Parameters:
  ///   - client: client containing the HTTP/2 channel and multiplexer to use for this call.
  ///   - path: path for this RPC method.
  ///   - callOptions: options to use when configuring this call.
  ///   - responseObserver: observer for received messages.
  init(
    client: GRPCClient,
    path: String,
    callOptions: CallOptions,
    responseObserver: ResponseObserver<ResponseMessage>
  ) {
    self.client = client
    self.streamPromise = client.channel.eventLoop.newPromise()
    self.clientChannelHandler = GRPCClientChannelHandler(
      initialMetadataPromise: client.channel.eventLoop.newPromise(),
      statusPromise: client.channel.eventLoop.newPromise(),
      responseObserver: responseObserver)

    self.createStreamChannel()
    self.setTimeout(callOptions.timeout)

    let requestHead = BaseClientCall<RequestMessage, ResponseMessage>.makeRequestHead(path: path, host: client.host, callOptions: callOptions)
    self.sendRequestHead(requestHead)
  }
}

extension BaseClientCall: ClientCall {
  /// HTTP/2 stream associated with this call.
  public var subchannel: EventLoopFuture<Channel> {
    return self.streamPromise.futureResult
  }

  /// Initial metadata returned from the server.
  public var initialMetadata: EventLoopFuture<HTTPHeaders> {
    return self.clientChannelHandler.initialMetadataPromise.futureResult
  }

  /// Status of this call which may originate from the server or client.
  ///
  /// Note: despite `GRPCStatus` being an `Error`, the value will be delievered as a __success__
  /// result even if the status represents a __negative__ outcome.
  public var status: EventLoopFuture<GRPCStatus> {
    return self.clientChannelHandler.statusPromise.futureResult
  }

  /// Cancel the current call.
  ///
  /// Closes the HTTP/2 stream once it becomes available. Additional writes to the channel will be ignored.
  /// Any unfulfilled promises will be failed with a cancelled status (excepting `status` which will be
  /// succeeded, if not already succeeded).
  public func cancel() {
    self.client.channel.eventLoop.execute {
      self.subchannel.whenSuccess { channel in
        channel.close(mode: .all, promise: nil)
      }
    }
  }
}

extension BaseClientCall {
  /// Creates and configures an HTTP/2 stream channel. `subchannel` will contain the stream channel when it is created.
  internal func createStreamChannel() {
    /// Create a new HTTP2 stream to handle calls.
    self.client.channel.eventLoop.execute {
      self.client.multiplexer.createStreamChannel(promise: self.streamPromise) { (subchannel, streamID) -> EventLoopFuture<Void> in
        subchannel.pipeline.addHandlers([HTTP2ToHTTP1ClientCodec(streamID: streamID, httpProtocol: .http),
                                         HTTP1ToRawGRPCClientCodec(),
                                         GRPCClientCodec<RequestMessage, ResponseMessage>(),
                                         self.clientChannelHandler],
                                        first: false)
      }
    }
  }

  /// Send the request head once `subchannel` becomes available.
  internal func sendRequestHead(_ requestHead: HTTPRequestHead) {
    self.subchannel.whenSuccess { channel in
      channel.write(GRPCClientRequestPart<RequestMessage>.head(requestHead), promise: nil)
    }
  }

  /// Send the given request once `subchannel` becomes available.
  internal func sendRequest(_ request: RequestMessage) {
    self.subchannel.whenSuccess { channel in
      channel.write(GRPCClientRequestPart<RequestMessage>.message(request), promise: nil)
    }
  }

  /// Send `end` once `subchannel` becomes available.
  internal func sendEnd() {
    self.subchannel.whenSuccess { channel in
      channel.writeAndFlush(GRPCClientRequestPart<RequestMessage>.end, promise: nil)
    }
  }

  /// Creates a client-side timeout for this call.
  internal func setTimeout(_ timeout: GRPCTimeout?) {
    guard let timeout = timeout else { return }

    let clientChannelHandler = self.clientChannelHandler
    self.client.channel.eventLoop.scheduleTask(in: timeout.asNIOTimeAmount) {
      let status = GRPCStatus(code: .deadlineExceeded, message: "client timed out after \(timeout)")
      clientChannelHandler.observeStatus(status)
    }
  }

  /// Makes a new `HTTPRequestHead` for this call.
  ///
  /// - Parameters:
  ///   - path: path for this RPC method.
  ///   - host: the address of the host we are connected to.
  ///   - callOptions: options to use when configuring this call.
  /// - Returns: `HTTPRequestHead` configured for this call.
  internal class func makeRequestHead(path: String, host: String, callOptions: CallOptions) -> HTTPRequestHead {
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
}
