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

/// A server-streaming gRPC call. The request is sent on initialization, each response is passed to the provided observer block.
///
/// The following futures are available to the caller:
/// - `initialMetadata`: the initial metadata returned from the server,
/// - `status`: the status of the gRPC call after it has ended,
/// - `trailingMetadata`: any metadata returned from the server alongside the `status`.
public class ServerStreamingClientCall<RequestMessage: Message, ResponseMessage: Message>: BaseClientCall<RequestMessage, ResponseMessage> {
  public init(client: GRPCClient, path: String, request: RequestMessage, callOptions: CallOptions, handler: @escaping (ResponseMessage) -> Void) {
    super.init(client: client, path: path, callOptions: callOptions, responseObserver: .callback(handler))

    let requestHead = self.makeRequestHead(path: path, host: client.host, callOptions: callOptions)
    self.sendHead(requestHead)
      .then { self._sendMessage(request) }
      .whenSuccess { self._sendEnd(promise: nil) }
  }
}
