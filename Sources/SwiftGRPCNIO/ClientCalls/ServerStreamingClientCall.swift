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

public class ServerStreamingClientCall<RequestMessage: Message, ResponseMessage: Message>: BaseClientCall<RequestMessage, ResponseMessage> {
  public init(client: GRPCClient, path: String, request: RequestMessage, callOptions: CallOptions, handler: @escaping (ResponseMessage) -> Void) {
    super.init(channel: client.channel, multiplexer: client.multiplexer, responseHandler: .callback(handler: handler))

    self.setTimeout(callOptions.timeout)

    let requestHead = self.makeRequestHead(path: path, host: client.host, customMetadata: callOptions.customMetadata)
    self.send(requestHead: requestHead, request: request)
  }
}
