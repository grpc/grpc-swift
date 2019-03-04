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
import _NIO1APIShims

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
public class ClientStreamingClientCall<RequestMessage: Message, ResponseMessage: Message>: BaseClientCall<RequestMessage, ResponseMessage>, StreamingRequestClientCall, UnaryResponseClientCall {
  public let response: EventLoopFuture<ResponseMessage>
  private var messageQueue: EventLoopFuture<Void>

  public init(client: GRPCClient, path: String, callOptions: CallOptions) {
    let responsePromise: EventLoopPromise<ResponseMessage> = client.channel.eventLoop.newPromise()
    self.response = responsePromise.futureResult
    self.messageQueue = client.channel.eventLoop.newSucceededFuture(result: ())

    super.init(
      client: client,
      path: path,
      callOptions: callOptions,
      responseObserver: .succeedPromise(responsePromise))

    let requestHead = self.makeRequestHead(path: path, host: client.host, callOptions: callOptions)
    self.messageQueue = self.messageQueue.then { self.sendHead(requestHead) }
  }

  public func sendMessage(_ message: RequestMessage) -> EventLoopFuture<Void> {
    return self._sendMessage(message)
  }

  public func sendMessage(_ message: RequestMessage, promise: EventLoopPromise<Void>?) {
    self._sendMessage(message, promise: promise)
  }

  public func sendEnd() -> EventLoopFuture<Void> {
    return self._sendEnd()
  }

  public func sendEnd(promise: EventLoopPromise<Void>?) {
    self._sendEnd(promise: promise)
  }

  public func newMessageQueue() -> EventLoopFuture<Void> {
    return self.messageQueue
  }
}
