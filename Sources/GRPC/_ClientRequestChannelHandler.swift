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
import NIOHTTP1

/// A base channel handler for client requests.
///
/// - Important: This is **NOT** part of the public API.
public class _ClientRequestChannelHandler<RequestMessage: Message>: ChannelInboundHandler {
  public typealias InboundIn = Never
  public typealias OutboundOut = GRPCClientRequestPart<RequestMessage>

  /// The request head to send.
  internal let requestHead: GRPCRequestHead

  init(requestHead: GRPCRequestHead) {
    self.requestHead = requestHead
  }

  public func channelActive(context: ChannelHandlerContext) {
    // If we don't provide a method here the default implementation on protocol (i.e. no-op) will be
    // used in subclasses, even if they implement channelActive(context:).
  }
}

/// A channel handler for unary client requests.
///
/// Sends the request head, message and end on `channelActive(context:)`.
///
/// - Important: This is **NOT** part of the public API.
public final class _UnaryRequestChannelHandler<RequestMessage: Message>: _ClientRequestChannelHandler<RequestMessage> {
  /// The request to send.
  internal let request: _Box<RequestMessage>

  public init(requestHead: GRPCRequestHead, request: _Box<RequestMessage>) {
    self.request = request
    super.init(requestHead: requestHead)
  }

  override public func channelActive(context: ChannelHandlerContext) {
    context.write(self.wrapOutboundOut(.head(self.requestHead)), promise: nil)
    context.write(self.wrapOutboundOut(.message(self.request)), promise: nil)
    context.writeAndFlush(self.wrapOutboundOut(.end), promise: nil)
    context.fireChannelActive()
  }
}

/// A channel handler for client calls which stream requests.
///
/// Sends the request head on `channelActive(context:)`.
///
/// - Important: This is **NOT** part of the public API.
public final class _StreamingRequestChannelHandler<RequestMessage: Message>: _ClientRequestChannelHandler<RequestMessage> {
  override public func channelActive(context: ChannelHandlerContext) {
    context.writeAndFlush(self.wrapOutboundOut(.head(self.requestHead)), promise: nil)
    context.fireChannelActive()
  }
}
