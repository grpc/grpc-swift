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

/// Provides a means for decoding incoming gRPC messages into protobuf objects.
///
/// Calls through to `processMessage` for individual messages it receives, which needs to be implemented by subclasses.
/// - Important: This is **NOT** part of the public API.
public class _BaseCallHandler<Request, Response>: GRPCCallHandler {
  public let _codec: ChannelHandler

  /// Called when the request head has been received.
  ///
  /// Overridden by subclasses.
  internal func processHead(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
    fatalError("needs to be overridden")
  }

  /// Called whenever a message has been received.
  ///
  /// Overridden by subclasses.
  internal func processMessage(_ message: Request) throws {
    fatalError("needs to be overridden")
  }

  /// Called when the client has half-closed the stream, indicating that they won't send any further data.
  ///
  /// Overridden by subclasses if the "end-of-stream" event is relevant.
  internal func endOfStreamReceived() throws { }

  /// Sends an error status to the client while ensuring that all call context promises are fulfilled.
  /// Because only the concrete call subclass knows which promises need to be fulfilled, this method needs to be overridden.
  internal func sendErrorStatus(_ status: GRPCStatus) {
    fatalError("needs to be overridden")
  }

  /// Whether this handler can still write messages to the client.
  private var serverCanWrite = true

  internal let callHandlerContext: CallHandlerContext

  internal var errorDelegate: ServerErrorDelegate? {
    return self.callHandlerContext.errorDelegate
  }

  internal var logger: Logger {
    return self.callHandlerContext.logger
  }

  internal init(
    callHandlerContext: CallHandlerContext,
    codec: ChannelHandler
  ) {
    self.callHandlerContext = callHandlerContext
    self._codec = codec
  }
}

extension _BaseCallHandler: ChannelInboundHandler {
  public typealias InboundIn = _GRPCServerRequestPart<Request>

  /// Passes errors to the user-provided `errorHandler`. After an error has been received an
  /// appropriate status is written. Errors which don't conform to `GRPCStatusTransformable`
  /// return a status with code `.internalError`.
  public func errorCaught(context: ChannelHandlerContext, error: Error) {
    let status: GRPCStatus

    if let errorWithContext = error as? GRPCError.WithContext {
      self.errorDelegate?.observeLibraryError(errorWithContext.error)
      status = self.errorDelegate?.transformLibraryError(errorWithContext.error)
          ?? errorWithContext.error.makeGRPCStatus()
    } else {
      self.errorDelegate?.observeLibraryError(error)
      status = self.errorDelegate?.transformLibraryError(error)
          ?? (error as? GRPCStatusTransformable)?.makeGRPCStatus()
          ?? .processingError
    }

    self.sendErrorStatus(status)
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch self.unwrapInboundIn(data) {
    case .head(let head):
      self.processHead(head, context: context)

    case .message(let message):
      do {
        try processMessage(message)
      } catch {
        self.logger.error("error caught while user handler was processing message", metadata: [MetadataKey.error: "\(error)"])
        self.errorCaught(context: context, error: error)
      }

    case .end:
      do {
        try endOfStreamReceived()
      } catch {
        self.logger.error("error caught on receiving end of stream", metadata: [MetadataKey.error: "\(error)"])
        self.errorCaught(context: context, error: error)
      }
    }
  }
}

extension _BaseCallHandler: ChannelOutboundHandler {
  public typealias OutboundIn = _GRPCServerResponsePart<Response>
  public typealias OutboundOut = _GRPCServerResponsePart<Response>

  public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    guard self.serverCanWrite else {
      promise?.fail(GRPCError.InvalidState("rpc has already finished").captureContext())
      return
    }

    // We can only write one status; make sure we don't write again.
    if case .statusAndTrailers = unwrapOutboundIn(data) {
      self.serverCanWrite = false
      context.writeAndFlush(data, promise: promise)
    } else {
      context.write(data, promise: promise)
    }
  }
}
