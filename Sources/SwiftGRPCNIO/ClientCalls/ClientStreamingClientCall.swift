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

/// A client-streaming gRPC call.
///
/// Messages should be sent via the `send` method; an `.end` message should be sent
/// to indicate the final message has been sent.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `response`: the response from the call,
/// - `status`: the status of the gRPC call,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public class ClientStreamingClientCall<RequestMessage: Message, ResponseMessage: Message>: BaseClientCall<RequestMessage, ResponseMessage>, StreamingRequestClientCall, UnaryResponseClientCall {
  public var response: EventLoopFuture<ResponseMessage> {
    // It's okay to force unwrap because we know the handler is holding the response promise.
    return self.clientChannelHandler.responsePromise!.futureResult
  }

  public init(client: GRPCClient, path: String, callOptions: CallOptions) {
    super.init(
      client: client,
      path: path,
      callOptions: callOptions,
      responseObserver: .succeedPromise(client.channel.eventLoop.newPromise()))
  }
}
