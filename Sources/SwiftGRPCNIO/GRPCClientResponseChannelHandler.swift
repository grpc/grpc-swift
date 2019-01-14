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
import SwiftProtobuf


public class GRPCClientResponseChannelHandler<ResponseMessage: Message> {
  private let messageObserver: (ResponseMessage) -> Void
  private let metadataPromise: EventLoopPromise<HTTPHeaders>
  private let statusPromise: EventLoopPromise<GRPCStatus>

  init(metadata: EventLoopPromise<HTTPHeaders>, status: EventLoopPromise<GRPCStatus>, messageHandler: ResponseMessageHandler) {
    self.metadataPromise = metadata
    self.statusPromise = status
    self.messageObserver = messageHandler.observer
  }

  enum ResponseMessageHandler {
    /// Fulfill the given promise on receiving the first response message.
    case fulfill(promise: EventLoopPromise<ResponseMessage>)

    /// Call the given handler for each response message received.
    case callback(handler: (ResponseMessage) -> Void)

    var observer: (ResponseMessage) -> Void {
      switch self {
      case .callback(let observer):
        return observer

      case .fulfill(let promise):
        return { promise.succeed(result: $0) }
      }
    }
  }
}


extension GRPCClientResponseChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = GRPCClientResponsePart<ResponseMessage>

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .headers(let headers):
      self.metadataPromise.succeed(result: headers)

    case .message(let message):
      self.messageObserver(message)

    case .status(let status):
      //! FIXME: error status codes should fail the response promise (if one exists).
      self.statusPromise.succeed(result: status)

      // We don't expect any more requests/responses beyond this point.
      _ = ctx.channel.close(mode: .all)
    }
  }
}
