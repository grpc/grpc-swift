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
import Logging

/// Abstract base class exposing a method to send multiple messages over the wire and a promise for the final RPC status.
///
/// - When `statusPromise` is fulfilled, the call is closed and the provided status transmitted.
/// - If `statusPromise` is failed and the error is of type `GRPCStatusTransformable`,
///   the result of `error.asGRPCStatus()` will be returned to the client.
/// - If `error.asGRPCStatus()` is not available, `GRPCStatus.processingError` is returned to the client.
open class StreamingResponseCallContext<ResponsePayload>: ServerCallContextBase {
  typealias WrappedResponse = _GRPCServerResponsePart<ResponsePayload>

  public let statusPromise: EventLoopPromise<GRPCStatus>

  public override init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.statusPromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, request: request, logger: logger)
  }

  /// Send a response to the client.
  ///
  /// - Parameter message: The message to send to the client.
  /// - Parameter compression: Whether compression should be used for this response. If compression
  ///   is enabled in the call context, the value passed here takes precedence. Defaults to deferring
  ///   to the value set on the call context.
  open func sendResponse(_ message: ResponsePayload, compression: Compression = .deferToCallDefault) -> EventLoopFuture<Void> {
    fatalError("needs to be overridden")
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used by our generated code.
open class StreamingResponseCallContextImpl<ResponsePayload>: StreamingResponseCallContext<ResponsePayload> {
  public let channel: Channel

  /// - Parameters:
  ///   - channel: The NIO channel the call is handled on.
  ///   - request: The headers provided with this call.
  ///   - errorDelegate: Provides a means for transforming status promise failures to `GRPCStatusTransformable` before
  ///     sending them to the client.
  ///
  ///     Note: `errorDelegate` is not called for status promise that are `succeeded` with a non-OK status.
  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, logger: Logger) {
    self.channel = channel

    super.init(eventLoop: channel.eventLoop, request: request, logger: logger)

    statusPromise.futureResult
      // Ensure that any error provided can be transformed to `GRPCStatus`, using "internal server error" as a fallback.
      .recover { [weak errorDelegate] error in
        errorDelegate?.observeRequestHandlerError(error, request: request)
        return errorDelegate?.transformRequestHandlerError(error, request: request)
          ?? (error as? GRPCStatusTransformable)?.makeGRPCStatus()
          ?? .processingError
      }
      // Finish the call by returning the final status.
      .whenSuccess {
        self.channel.writeAndFlush(NIOAny(WrappedResponse.statusAndTrailers($0, self.trailingMetadata)), promise: nil)
    }
  }

  open override func sendResponse(_ message: ResponsePayload, compression: Compression = .deferToCallDefault) -> EventLoopFuture<Void> {
    let messageContext = _MessageContext(message, compressed: compression.isEnabled(callDefault: self.compressionEnabled))
    return self.channel.writeAndFlush(NIOAny(WrappedResponse.message(messageContext)))
  }
}

/// Concrete implementation of `StreamingResponseCallContext` used for testing.
///
/// Simply records all sent messages.
open class StreamingResponseCallContextTestStub<ResponsePayload>: StreamingResponseCallContext<ResponsePayload> {
  open var recordedResponses: [ResponsePayload] = []

  open override func sendResponse(_ message: ResponsePayload, compression: Compression = .deferToCallDefault) -> EventLoopFuture<Void> {
    recordedResponses.append(message)
    return eventLoop.makeSucceededFuture(())
  }
}
