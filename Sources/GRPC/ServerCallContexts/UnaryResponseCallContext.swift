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

/// Abstract base class exposing a method that exposes a promise for the RPC response.
///
/// - When `responsePromise` is fulfilled, the call is closed and the provided response transmitted with status `responseStatus` (`.ok` by default).
/// - If `statusPromise` is failed and the error is of type `GRPCStatusTransformable`,
///   the result of `error.asGRPCStatus()` will be returned to the client.
/// - If `error.asGRPCStatus()` is not available, `GRPCStatus.processingError` is returned to the client.
///
/// For unary calls, the response is not actually provided by fulfilling `responsePromise`, but instead by completing
/// the future returned by `UnaryCallHandler.EventObserver`.
open class UnaryResponseCallContext<ResponsePayload>: ServerCallContextBase, StatusOnlyCallContext {
  typealias WrappedResponse = _GRPCServerResponsePart<ResponsePayload>

  public let responsePromise: EventLoopPromise<ResponsePayload>
  public var responseStatus: GRPCStatus = .ok

  public override init(eventLoop: EventLoop, request: HTTPRequestHead, logger: Logger) {
    self.responsePromise = eventLoop.makePromise()
    super.init(eventLoop: eventLoop, request: request, logger: logger)
  }
}

/// Protocol variant of `UnaryResponseCallContext` that only exposes the `responseStatus` and `trailingMetadata`
/// fields, but not `responsePromise`.
///
/// Motivation: `UnaryCallHandler` already asks the call handler return an `EventLoopFuture<ResponsePayload>` which
/// is automatically cascaded into `UnaryResponseCallContext.responsePromise`, so that promise does not (and should not)
/// be fulfilled by the user.
///
/// We can use a protocol (instead of an abstract base class) here because removing the generic `responsePromise` field
/// lets us avoid associated-type requirements on the protocol.
public protocol StatusOnlyCallContext: ServerCallContext {
  var responseStatus: GRPCStatus { get set }
  var trailingMetadata: HTTPHeaders { get set }
}

/// Concrete implementation of `UnaryResponseCallContext` used by our generated code.
open class UnaryResponseCallContextImpl<ResponsePayload>: UnaryResponseCallContext<ResponsePayload> {
  public let channel: Channel

  /// - Parameters:
  ///   - channel: The NIO channel the call is handled on.
  ///   - request: The headers provided with this call.
  ///   - errorDelegate: Provides a means for transforming response promise failures to `GRPCStatusTransformable` before
  ///     sending them to the client.
  public init(channel: Channel, request: HTTPRequestHead, errorDelegate: ServerErrorDelegate?, logger: Logger) {
    self.channel = channel

    super.init(eventLoop: channel.eventLoop, request: request, logger: logger)

    responsePromise.futureResult
      .whenComplete { [self, weak errorDelegate] result in
        let statusAndMetadata: GRPCStatusAndMetadata

        switch result {
        case .success(let responseMessage):
          self.channel.write(NIOAny(WrappedResponse.message(.init(responseMessage, compressed: self.compressionEnabled))), promise: nil)
          statusAndMetadata = GRPCStatusAndMetadata(status: self.responseStatus, metadata: nil)
        case .failure(let error):
          errorDelegate?.observeRequestHandlerError(error, request: request)

          if let transformed: GRPCStatusAndMetadata = errorDelegate?.transformRequestHandlerError(error, request: request) {
            statusAndMetadata = transformed
          } else if let grpcStatusTransformable = error as? GRPCStatusTransformable {
            statusAndMetadata = GRPCStatusAndMetadata(status: grpcStatusTransformable.makeGRPCStatus(), metadata: nil)
          } else {
            statusAndMetadata = GRPCStatusAndMetadata(status: .processingError, metadata: nil)
          }
        }

        if let metadata = statusAndMetadata.metadata {
          self.trailingMetadata.add(contentsOf: metadata)
        }
        self.channel.writeAndFlush(NIOAny(WrappedResponse.statusAndTrailers(statusAndMetadata.status, self.trailingMetadata)), promise: nil)
      }
  }
}

/// Concrete implementation of `UnaryResponseCallContext` used for testing.
///
/// Only provided to make it clear in tests that no "real" implementation is used.
open class UnaryResponseCallContextTestStub<ResponsePayload>: UnaryResponseCallContext<ResponsePayload> { }
