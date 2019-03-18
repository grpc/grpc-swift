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

/// A unary gRPC call. The request is sent on initialization.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `response`: the response from the unary call,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public class UnaryClientCall<RequestMessage: Message, ResponseMessage: Message>: BaseClientCall<RequestMessage, ResponseMessage>, UnaryResponseClientCall {
  public let response: EventLoopFuture<ResponseMessage>

  public init(client: GRPCClient, path: String, request: RequestMessage, callOptions: CallOptions) {
    let responsePromise: EventLoopPromise<ResponseMessage> = client.channel.eventLoop.makePromise()
    self.response = responsePromise.futureResult

    super.init(
      client: client,
      path: path,
      callOptions: callOptions,
      responseObserver: .succeedPromise(responsePromise))

    let requestHead = self.makeRequestHead(path: path, host: client.host, callOptions: callOptions)
    self.sendHead(requestHead)
      .flatMap { self._sendMessage(request) }
      .whenSuccess { self._sendEnd(promise: nil) }
  }
}
