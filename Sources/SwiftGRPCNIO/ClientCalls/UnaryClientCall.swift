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

public class UnaryClientCall<Request: Message, Response: Message>: BaseClientCall<Request, Response>, UnaryResponseClientCall {
  public let response: EventLoopFuture<Response>

  public init(client: GRPCClient, path: String, request: Request) {
    let responsePromise: EventLoopPromise<Response> = client.channel.eventLoop.newPromise()
    self.response = responsePromise.futureResult

    super.init(channel: client.channel, multiplexer: client.multiplexer, responseHandler: .fulfill(promise: responsePromise))

    let requestHead = makeRequestHead(path: path, host: client.host)
    subchannel.whenSuccess { channel in
      channel.write(GRPCClientRequestPart<Request>.head(requestHead), promise: nil)
      channel.write(GRPCClientRequestPart<Request>.message(request), promise: nil)
      channel.writeAndFlush(GRPCClientRequestPart<Request>.end, promise: nil)
    }
  }
}
