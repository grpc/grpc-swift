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
import NIOHTTP2
import NIOHPACK
import Logging

/// A unary gRPC call. The request is sent on initialization.
public final class UnaryCall<
  RequestPayload: GRPCPayload,
  ResponsePayload: GRPCPayload
>: UnaryResponseClientCall {
  private let transport: ChannelTransport<RequestPayload, ResponsePayload>

  /// The options used to make the RPC.
  public let options: CallOptions

  /// The `Channel` used to transport messages for this RPC.
  public var subchannel: EventLoopFuture<Channel> {
    return self.transport.streamChannel()
  }

  /// The `EventLoop` this call is running on.
  public var eventLoop: EventLoop {
    return self.transport.eventLoop
  }

  /// Cancel this RPC if it hasn't already completed.
  public func cancel(promise: EventLoopPromise<Void>?) {
    self.transport.cancel(promise: promise)
  }

  // MARK: - Response Parts

  /// The initial metadata returned from the server.
  public var initialMetadata: EventLoopFuture<HPACKHeaders> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyInitialMetadataPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyInitialMetadataPromise.getFutureResult()
      }
    }
  }

  /// The response returned by the server.
  public let response: EventLoopFuture<ResponsePayload>

  /// The trailing metadata returned from the server.
  public var trailingMetadata: EventLoopFuture<HPACKHeaders> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyTrailingMetadataPromise.getFutureResult()
      }
    }
  }

  /// The final status of the the RPC.
  public var status: EventLoopFuture<GRPCStatus> {
    if self.eventLoop.inEventLoop {
      return self.transport.responseContainer.lazyStatusPromise.getFutureResult()
    } else {
      return self.eventLoop.flatSubmit {
        return self.transport.responseContainer.lazyStatusPromise.getFutureResult()
      }
    }
  }

  internal init(
    response: EventLoopFuture<ResponsePayload>,
    transport: ChannelTransport<RequestPayload, ResponsePayload>,
    options: CallOptions
  ) {
    self.response = response
    self.transport = transport
    self.options = options
  }

  internal func send(_ head: _GRPCRequestHead, request: RequestPayload) {
    self.transport.sendUnary(head, request: request, compressed: self.options.messageEncoding.enabledForRequests)
  }
}

extension UnaryCall {
  internal static func makeOnHTTP2Stream(
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    callOptions: CallOptions,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger
  ) -> UnaryCall<RequestPayload, ResponsePayload> {
    let eventLoop = multiplexer.eventLoop
    let responsePromise: EventLoopPromise<ResponsePayload> = eventLoop.makePromise()
    let transport = ChannelTransport<RequestPayload, ResponsePayload>(
      multiplexer: multiplexer,
      responseContainer: .init(eventLoop: eventLoop, unaryResponsePromise: responsePromise),
      callType: .unary,
      timeLimit: callOptions.timeLimit,
      errorDelegate: errorDelegate,
      logger: logger
    )
    return UnaryCall(response: responsePromise.futureResult, transport: transport, options: callOptions)
  }
}
