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

/// A handler which redirects all writes into a callback until the `.end` part is seen, after which
/// all writes will be failed.
///
/// This handler is intended for use with 'fake' response streams the 'FakeChannel'.
internal final class WriteCapturingHandler<Request: GRPCPayload>: ChannelOutboundHandler {
  typealias OutboundIn = _GRPCClientRequestPart<Request>
  typealias RequestHandler = (FakeRequestPart<Request>) -> ()

  private var state: State
  private enum State {
    case active(RequestHandler)
    case inactive
  }

  internal init(requestHandler: @escaping RequestHandler) {
    self.state = .active(requestHandler)
  }

  internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    guard case let .active(handler) = self.state else {
      promise?.fail(ChannelError.ioOnClosedChannel)
      return
    }

    switch self.unwrapOutboundIn(data) {
    case .head(let requestHead):
      handler(.metadata(requestHead.customMetadata))

    case .message(let messageContext):
      handler(.message(messageContext.message))

    case .end:
      handler(.end)
      // We're done now.
      self.state = .inactive
    }

    promise?.succeed(())
  }
}
