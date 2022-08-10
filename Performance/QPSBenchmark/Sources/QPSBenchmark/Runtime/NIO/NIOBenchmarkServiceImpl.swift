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

import Foundation
import GRPC
import NIOCore

/// Implementation of asynchronous service for benchmarking.
final class NIOBenchmarkServiceImpl: Grpc_Testing_BenchmarkServiceProvider {
  let interceptors: Grpc_Testing_BenchmarkServiceServerInterceptorFactoryProtocol? = nil

  /// One request followed by one response.
  /// The server returns the client payload as-is.
  func unaryCall(
    request: Grpc_Testing_SimpleRequest,
    context: StatusOnlyCallContext
  ) -> EventLoopFuture<Grpc_Testing_SimpleResponse> {
    do {
      return context.eventLoop
        .makeSucceededFuture(try NIOBenchmarkServiceImpl.processSimpleRPC(request: request))
    } catch {
      return context.eventLoop.makeFailedFuture(error)
    }
  }

  /// Repeated sequence of one request followed by one response.
  /// Should be called streaming ping-pong
  /// The server returns the client payload as-is on each response
  func streamingCall(
    context: StreamingResponseCallContext<Grpc_Testing_SimpleResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_SimpleRequest>) -> Void> {
    return context.eventLoop.makeSucceededFuture({ event in
      switch event {
      case let .message(request):
        do {
          let response = try NIOBenchmarkServiceImpl.processSimpleRPC(request: request)
          context.sendResponse(response, promise: nil)
        } catch {
          context.statusPromise.fail(error)
        }
      case .end:
        context.statusPromise.succeed(.ok)
      }
    })
  }

  /// Single-sided unbounded streaming from client to server
  /// The server returns the client payload as-is once the client does WritesDone
  func streamingFromClient(
    context: UnaryResponseCallContext<Grpc_Testing_SimpleResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_SimpleRequest>) -> Void> {
    context.logger.warning("streamingFromClient not implemented yet")
    return context.eventLoop.makeFailedFuture(GRPCStatus(
      code: GRPCStatus.Code.unimplemented,
      message: "Not implemented"
    ))
  }

  /// Single-sided unbounded streaming from server to client
  /// The server repeatedly returns the client payload as-is
  func streamingFromServer(
    request: Grpc_Testing_SimpleRequest,
    context: StreamingResponseCallContext<Grpc_Testing_SimpleResponse>
  ) -> EventLoopFuture<GRPCStatus> {
    context.logger.warning("streamingFromServer not implemented yet")
    return context.eventLoop.makeFailedFuture(GRPCStatus(
      code: GRPCStatus.Code.unimplemented,
      message: "Not implemented"
    ))
  }

  /// Two-sided unbounded streaming between server to client
  /// Both sides send the content of their own choice to the other
  func streamingBothWays(
    context: StreamingResponseCallContext<Grpc_Testing_SimpleResponse>
  ) -> EventLoopFuture<(StreamEvent<Grpc_Testing_SimpleRequest>) -> Void> {
    context.logger.warning("streamingBothWays not implemented yet")
    return context.eventLoop.makeFailedFuture(GRPCStatus(
      code: GRPCStatus.Code.unimplemented,
      message: "Not implemented"
    ))
  }

  /// Make a payload for sending back to the client.
  private static func makePayload(
    type: Grpc_Testing_PayloadType,
    size: Int
  ) throws -> Grpc_Testing_Payload {
    if type != .compressable {
      // Making a payload which is not compressable is hard - and not implemented in
      // other implementations too.
      throw GRPCStatus(code: .internalError, message: "Failed to make payload")
    }
    var payload = Grpc_Testing_Payload()
    payload.body = Data(count: size)
    payload.type = type
    return payload
  }

  /// Process a simple RPC.
  /// - parameters:
  ///     - request: The request from the client.
  /// - returns: A response to send back to the client.
  private static func processSimpleRPC(
    request: Grpc_Testing_SimpleRequest
  ) throws -> Grpc_Testing_SimpleResponse {
    var response = Grpc_Testing_SimpleResponse()
    if request.responseSize > 0 {
      response.payload = try self.makePayload(
        type: request.responseType,
        size: Int(request.responseSize)
      )
    }
    return response
  }
}
