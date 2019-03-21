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

/// This class provides much of the boilerplate for the four types of gRPC call objects returned to framework
/// users.
///
/// Setup includes:
/// - creation of an HTTP/2 stream for the call to execute on,
/// - configuration of the NIO channel handlers for the stream, and
/// - setting a call timeout, if one is provided.
///
/// This class also provides much of the framework user facing functionality via conformance to `ClientCall`.
open class BaseClientCall<RequestMessage: Message, ResponseMessage: Message> {
  /// The underlying `GRPCClient` providing the HTTP/2 channel and multiplexer.
  internal let client: GRPCClient

  /// Promise for an HTTP/2 stream to execute the call on.
  internal let streamPromise: EventLoopPromise<Channel>

  /// Client channel handler. Handles internal state for reading/writing messages to the channel.
  /// The handler also owns the promises for the futures that this class surfaces to the user (such as
  /// `initialMetadata` and `status`).
  internal let clientChannelHandler: GRPCClientChannelHandler<RequestMessage, ResponseMessage>

  /// Sets up a gRPC call.
  ///
  /// A number of actions are performed:
  /// - a new HTTP/2 stream is created and configured using the channel and multiplexer provided by `client`,
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
  }
}

extension BaseClientCall: ClientCall {
  public var subchannel: EventLoopFuture<Channel> {
    return self.streamPromise.futureResult
  }

  public var initialMetadata: EventLoopFuture<HTTPHeaders> {
    return self.clientChannelHandler.initialMetadataPromise.futureResult
  }

  public var status: EventLoopFuture<GRPCStatus> {
    return self.clientChannelHandler.statusPromise.futureResult
  }

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
  ///
  /// - Important: This should only ever be called once.
  private func createStreamChannel() {
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
  ///
  /// - Important: This should only ever be called once.
  ///
  /// - Parameters:
  ///   - requestHead: The request head to send.
  ///   - promise: A promise to fulfill once the request head has been sent.
  internal func sendHead(_ requestHead: HTTPRequestHead, promise: EventLoopPromise<Void>?) {
    // The nghttp2 implementation of NIOHTTP2 has a known defect where "promises on control frame
    // writes do not work and will be leaked. Promises on DATA frame writes work just fine and will
    // be fulfilled correctly." Succeed the promise here as a temporary workaround.
    //! TODO: remove this and pass the promise to `writeAndFlush` when NIOHTTP2 supports it.
    promise?.succeed(result: ())
    self.subchannel.whenSuccess { channel in
      channel.writeAndFlush(GRPCClientRequestPart<RequestMessage>.head(requestHead), promise: nil)
    }
  }

  /// Send the request head once `subchannel` becomes available.
  ///
  /// - Important: This should only ever be called once.
  ///
  /// - Parameter requestHead: The request head to send.
  /// - Returns: A future which will be succeeded once the request head has been sent.
  internal func sendHead(_ requestHead: HTTPRequestHead) -> EventLoopFuture<Void> {
    let promise = client.channel.eventLoop.newPromise(of: Void.self)
    self.sendHead(requestHead, promise: promise)
    return promise.futureResult
  }

  /// Send the given message once `subchannel` becomes available.
  ///
  /// - Note: This is prefixed to allow for classes conforming to `StreamingRequestClientCall` to use the non-underbarred name.
  /// - Parameters:
  ///   - message: The message to send.
  ///   - promise: A promise to fulfil when the message reaches the network.
  internal func _sendMessage(_ message: RequestMessage, promise: EventLoopPromise<Void>?) {
    self.subchannel.whenSuccess { channel in
      channel.writeAndFlush(GRPCClientRequestPart<RequestMessage>.message(message), promise: promise)
    }
  }

  /// Send the given message once `subchannel` becomes available.
  ///
  /// - Note: This is prefixed to allow for classes conforming to `StreamingRequestClientCall` to use the non-underbarred name.
  /// - Returns: A future which will be fullfilled when the message reaches the network.
  internal func _sendMessage(_ message: RequestMessage) -> EventLoopFuture<Void> {
    let promise = client.channel.eventLoop.newPromise(of: Void.self)
    self._sendMessage(message, promise: promise)
    return promise.futureResult
  }

  /// Send `end` once `subchannel` becomes available.
  ///
  /// - Note: This is prefixed to allow for classes conforming to `StreamingRequestClientCall` to use the non-underbarred name.
  /// - Important: This should only ever be called once.
  /// - Parameter promise: A promise to succeed once then end has been sent.
  internal func _sendEnd(promise: EventLoopPromise<Void>?) {
    // The nghttp2 implementation of NIOHTTP2 has a known defect where "promises on control frame
    // writes do not work and will be leaked. Promises on DATA frame writes work just fine and will
    // be fulfilled correctly." Succeed the promise here as a temporary workaround.
    //! TODO: remove this and pass the promise to `writeAndFlush` when NIOHTTP2 supports it.
    promise?.succeed(result: ())
    self.subchannel.whenSuccess { channel in
      channel.writeAndFlush(GRPCClientRequestPart<RequestMessage>.end, promise: nil)
    }
  }

  /// Send `end` once `subchannel` becomes available.
  ///
  /// - Note: This is prefixed to allow for classes conforming to `StreamingRequestClientCall` to use the non-underbarred name.
  /// - Important: This should only ever be called once.
  ///- Returns: A future which will be succeeded once the end has been sent.
  internal func _sendEnd() -> EventLoopFuture<Void> {
    let promise = client.channel.eventLoop.newPromise(of: Void.self)
    self._sendEnd(promise: promise)
    return promise.futureResult
  }

  /// Creates a client-side timeout for this call.
  ///
  /// - Important: This should only ever be called once.
  private func setTimeout(_ timeout: GRPCTimeout) {
    if timeout == .infinite { return }

    self.client.channel.eventLoop.scheduleTask(in: timeout.asNIOTimeAmount) { [weak self] in
      self?.clientChannelHandler.observeError(.client(.deadlineExceeded(timeout)))
    }
  }

  /// Makes a new `HTTPRequestHead` for a call with this signature.
  ///
  /// - Parameters:
  ///   - path: path for this RPC method.
  ///   - host: the address of the host we are connected to.
  ///   - callOptions: options to use when configuring this call.
  /// - Returns: `HTTPRequestHead` configured for this call.
  internal func makeRequestHead(path: String, host: String, callOptions: CallOptions) -> HTTPRequestHead {
    var requestHead = HTTPRequestHead(version: .init(major: 2, minor: 0), method: .POST, uri: path)

    callOptions.customMetadata.forEach { name, value in
      requestHead.headers.add(name: name, value: value)
    }

    // We're dealing with HTTP/1; the NIO HTTP2ToHTTP1Codec replaces "host" with ":authority".
    requestHead.headers.add(name: "host", value: host)

    requestHead.headers.add(name: "content-type", value: "application/grpc")

    // Used to detect incompatible proxies, as per https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#requests
    requestHead.headers.add(name: "te", value: "trailers")

    //! FIXME: Add a more specific user-agent, see: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md#user-agents
    requestHead.headers.add(name: "user-agent", value: "grpc-swift-nio")

    requestHead.headers.add(name: "grpc-accept-encoding", value: CompressionMechanism.acceptEncodingHeader)

    if callOptions.timeout != .infinite {
      requestHead.headers.add(name: "grpc-timeout", value: String(describing: callOptions.timeout))
    }

    return requestHead
  }
}
