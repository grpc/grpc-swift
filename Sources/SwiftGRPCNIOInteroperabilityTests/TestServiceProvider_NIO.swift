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
import SwiftGRPCNIO
import NIO

/// A service prodiver for the gRPC interoperaability test suite.
///
/// See: https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md#server
public class TestServiceProvider_NIO: Grpc_Testing_TestServiceProvider_NIO {
  public init() { }

  /// Features that this server implements.
  public static var implementedFeatures: Set<ServerFeature> {
    return [
      .emptyCall,
      .unaryCall,
      .streamingOutputCall,
      .streamingInputCall,
      .fullDuplexCall,
      .echoStatus
    ]
  }

  /// Server implements `emptyCall` which immediately returns the empty message.
  public func emptyCall(
    request: Grpc_Testing_Empty,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Grpc_Testing_Empty> {
    return context.eventLoop.makeSucceededFuture(Grpc_Testing_Empty())
  }

  /// Server implements `unaryCall` which immediately returns a `SimpleResponse` with a payload
  /// body of size `SimpleRequest.responseSize` bytes and type as appropriate for the
  /// `SimpleRequest.responseType`.
  ///
  /// If the server does not support the `responseType`, then it should fail the RPC with
  /// `INVALID_ARGUMENT`.
  public func unaryCall(
    request: Grpc_Testing_SimpleRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Grpc_Testing_SimpleResponse> {
    let promise = context.eventLoop.makePromise(of: Grpc_Testing_SimpleResponse.self)
    if request.shouldEchoStatus {
      let code = StatusCode(rawValue: numericCast(request.responseStatus.code)) ?? .unknown
      promise.fail(GRPCStatus(code: code, message: request.responseStatus.message))
    } else if context.request.headers.shouldEchoMetadata {
      promise.fail(GRPCStatus(code: .unimplemented, message: "Echoing metadata is not yet supported"))
    } else if case .UNRECOGNIZED = request.responseType {
      promise.fail(GRPCStatus(code: .invalidArgument, message: nil))
    } else {
      let response = Grpc_Testing_SimpleResponse.with { response in
        response.payload = Grpc_Testing_Payload.with { payload in
          payload.body = Data(repeating: 0, count: numericCast(request.responseSize))
          payload.type = request.responseType
        }
      }
      promise.succeed(response)
    }

    return promise.futureResult
  }

  /// Server gets the default `SimpleRequest` proto as the request. The content of the request is
  /// ignored. It returns the `SimpleResponse` proto with the payload set to current timestamp.
  /// The timestamp is an integer representing current time with nanosecond resolution. This
  /// integer is formated as ASCII decimal in the response. The format is not really important as
  /// long as the response payload is different for each request. In addition it adds cache control
  /// headers such that the response can be cached by proxies in the response path. Server should
  /// be behind a caching proxy for this test to pass. Currently we set the max-age to 60 seconds.
  public func cacheableUnaryCall(
    request: Grpc_Testing_SimpleRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Grpc_Testing_SimpleResponse> {
    let status = GRPCStatus(
      code: .unimplemented,
      message: "'cacheableUnaryCall' requires control of the initial metadata which isn't supported"
    )

    return context.eventLoop.makeFailedFuture(status)
  }

  /// Server implements `streamingOutputCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in `StreamingOutputCallRequest`.
  /// Each `StreamingOutputCallResponse` should have a payload body of size `ResponseParameter.size`
  /// bytes, as specified by its respective `ResponseParameter`. After sending all responses, it
  /// closes with OK.
  public func streamingOutputCall(
    request: Grpc_Testing_StreamingOutputCallRequest,
    context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    var responseQueue = context.eventLoop.makeSucceededFuture(())

    for responseParameter in request.responseParameters {
      responseQueue = responseQueue.flatMap {
        let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
          response.payload = Grpc_Testing_Payload.with { payload in
            payload.body = Data(repeating: 0, count: numericCast(responseParameter.size))
          }
        }

        return context.sendResponse(response)
      }
    }

    return responseQueue.map { GRPCStatus.ok }
  }

  /// Server implements `streamingInputCall` which upon half close immediately returns a
  /// `StreamingInputCallResponse` where `aggregatedPayloadSize` is the sum of all request payload
  /// bodies received.
  public func streamingInputCall(
    context: UnaryResponseCallContext<Grpc_Testing_StreamingInputCallResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingInputCallRequest>) -> Void> {
    var aggregatePayloadSize = 0

    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case .message(let request):
        aggregatePayloadSize += request.payload.body.count

      case .end:
        context.responsePromise.succeed(Grpc_Testing_StreamingInputCallResponse.with { response in
          response.aggregatedPayloadSize = numericCast(aggregatePayloadSize)
        })
      }

    })
  }

  /// Server implements `fullDuplexCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in each
  /// `StreamingOutputCallRequest`. Each `StreamingOutputCallResponse` should have a payload body
  /// of size `ResponseParameter.size` bytes, as specified by its respective `ResponseParameter`s.
  /// After receiving half close and sending all responses, it closes with OK.
  public func fullDuplexCall(
    context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingOutputCallRequest>) -> Void> {
    // We don't have support for this yet so just fail the call.
    if context.request.headers.shouldEchoMetadata {
      let status = GRPCStatus(
        code: .unimplemented,
        message: "'cacheableUnaryCall' requires control of the initial/trailing metadata which isn't supported"
      )
      return context.eventLoop.makeFailedFuture(status)
    }

    var sendQueue = context.eventLoop.makeSucceededFuture(())

    func streamHandler(_ event: StreamEvent<Grpc_Testing_StreamingOutputCallRequest>) {
      switch event {
      case .message(let message):
        if message.shouldEchoStatus {
          let code = StatusCode(rawValue: numericCast(message.responseStatus.code))
          let status = GRPCStatus(code: code ?? .unknown, message: message.responseStatus.message)
          context.statusPromise.succeed(status)
        } else {
          for responseParameter in message.responseParameters {
            let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
              response.payload = .zeros(count: numericCast(responseParameter.size))
            }

            sendQueue = sendQueue.flatMap {
              context.sendResponse(response)
            }
          }
        }

      case .end:
        sendQueue.map { GRPCStatus.ok }.cascade(to: context.statusPromise)
      }
    }

    return context.eventLoop.makeSucceededFuture(streamHandler(_:))
  }

  /// This is not implemented as it is not described in the specification.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
  public func halfDuplexCall(
    context: StreamingResponseCallContext<Grpc_Testing_StreamingOutputCallResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_StreamingOutputCallRequest>) -> Void> {
    let status = GRPCStatus(
      code: .unimplemented,
      message: "'halfDuplexCall' was not described in the specification"
    )

    return context.eventLoop.makeFailedFuture(status)
  }
}
