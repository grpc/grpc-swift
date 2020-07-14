/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import NIO

/// An inbound channel handler which forwards events and messages to a client call.
internal class GRPCClientCallHandler<Request, Response>: ChannelInboundHandler {
  typealias InboundIn = _GRPCClientResponsePart<Response>
  private var call: ChannelTransport<Request, Response>

  init(call: ChannelTransport<Request, Response>) {
    self.call = call
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    self.call.receiveError(error)
    context.fireErrorCaught(error)
  }

  func channelActive(context: ChannelHandlerContext) {
    self.call.activate(stream: context.channel)
    context.fireChannelActive()
  }

  func channelInactive(context: ChannelHandlerContext) {
    self.errorCaught(context: context, error: GRPCStatus(code: .unavailable, message: nil))
    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = self.unwrapInboundIn(data)
    self.call.receiveResponse(part)
  }
}

