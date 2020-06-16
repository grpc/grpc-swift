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
import NIO
import NIOHTTP2
import NIOHPACK
import Logging

/// A server-streaming gRPC call. The request is sent on initialization, each response is passed to
/// the provided observer block.
public final class ServerStreamingCall<
  RequestPayload: GRPCPayload,
  ResponsePayload: GRPCPayload
>: ClientCall {
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
  
  init(
    path: String,
    scheme: String,
    authority: String,
    callOptions: CallOptions,
    eventLoop: EventLoop,
    multiplexer: EventLoopFuture<HTTP2StreamMultiplexer>,
    errorDelegate: ClientErrorDelegate?,
    logger: Logger,
    request: RequestPayload,
    handler: @escaping (ResponsePayload) -> Void
  ) {
    let requestID = callOptions.requestIDProvider.requestID()
    var logger = logger
    logger[metadataKey: MetadataKey.requestID] = "\(requestID)"
    logger[metadataKey: "path"] = "\(path)"

    self.transport = ChannelTransport(
      multiplexer: multiplexer,
      responseContainer: .init(eventLoop: eventLoop, streamingResponseHandler: handler),
      callType: .serverStreaming,
      timeLimit: callOptions.timeLimit,
      errorDelegate: errorDelegate,
      logger: logger
    )

    self.options = callOptions

    let requestHead = _GRPCRequestHead(
      scheme: scheme,
      path: path,
      host: authority,
      requestID: requestID,
      options: callOptions
    )

    self.transport.sendUnary(
      requestHead,
      request: request,
      compressed: callOptions.messageEncoding.enabledForRequests
    )
  }
}
