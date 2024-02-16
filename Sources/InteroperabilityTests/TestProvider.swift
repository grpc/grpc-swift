/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
import GRPCCore

@available(macOS 13.0, *)
public struct TestProvider: Grpc_Testing_TestService.ServiceProtocol {
  public func unimplementedCall(
    request: GRPCCore.ServerRequest.Single<Grpc_Testing_TestService.Method.UnimplementedCall.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Single<Grpc_Testing_TestService.Method.UnimplementedCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }

  /// Server implements `emptyCall` which immediately returns the empty message.
  public func emptyCall(
    request: GRPCCore.ServerRequest.Single<Grpc_Testing_TestService.Method.EmptyCall.Input>
  ) async throws -> GRPCCore.ServerResponse.Single<Grpc_Testing_TestService.Method.EmptyCall.Output>
  {
    let message = Grpc_Testing_TestService.Method.EmptyCall.Output()
    return GRPCCore.ServerResponse.Single(message: message)
  }

  /// Server implements `unaryCall` which immediately returns a `SimpleResponse` with a payload
  /// body of size `SimpleRequest.responseSize` bytes and type as appropriate for the
  /// `SimpleRequest.responseType`.
  ///
  /// If the server does not support the `responseType`, then it should fail the RPC with
  /// `INVALID_ARGUMENT`.
  public func unaryCall(
    request: GRPCCore.ServerRequest.Single<Grpc_Testing_TestService.Method.UnaryCall.Input>
  ) async throws -> GRPCCore.ServerResponse.Single<Grpc_Testing_TestService.Method.UnaryCall.Output>
  {
    if request.message.responseStatus.isInitialized {
      let code = Status.Code(rawValue: Int(request.message.responseStatus.code))
      let status = Status.init(
        code: code ?? .unknown,
        message: request.message.responseStatus.message
      )
      if let error = GRPCCore.RPCError(status: status) {
        throw error
      }
    }

    if case .UNRECOGNIZED = request.message.responseType {
      throw RPCError(code: .invalidArgument, message: "The response type is not recognized.")
    }

    let responseMessage = Grpc_Testing_TestService.Method.UnaryCall.Output.with { response in
      response.payload = Grpc_Testing_Payload.with { payload in
        payload.body = Data(repeating: 0, count: Int(request.message.responseSize))
        payload.type = request.message.responseType
      }
    }

    return ServerResponse.Single(message: responseMessage)
  }

  /// Server gets the default `SimpleRequest` proto as the request. The content of the request is
  /// ignored. It returns the `SimpleResponse` proto with the payload set to current timestamp.
  /// The timestamp is an integer representing current time with nanosecond resolution. This
  /// integer is formated as ASCII decimal in the response. The format is not really important as
  /// long as the response payload is different for each request. In addition it adds cache control
  /// headers such that the response can be cached by proxies in the response path. Server should
  /// be behind a caching proxy for this test to pass. Currently we set the max-age to 60 seconds.
  public func cacheableUnaryCall(
    request: GRPCCore.ServerRequest.Single<Grpc_Testing_TestService.Method.CacheableUnaryCall.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Single<Grpc_Testing_TestService.Method.CacheableUnaryCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }

  /// Server implements `streamingOutputCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in `StreamingOutputCallRequest`.
  /// Each `StreamingOutputCallResponse` should have a payload body of size `ResponseParameter.size`
  /// bytes, as specified by its respective `ResponseParameter`. After sending all responses, it
  /// closes with OK.
  public func streamingOutputCall(
    request: GRPCCore.ServerRequest.Single<
      Grpc_Testing_TestService.Method.StreamingOutputCall.Input
    >
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_TestService.Method.StreamingOutputCall.Output>
  {
    return ServerResponse.Stream { writer in
      for responseParameter in request.message.responseParameters {
        let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
          response.payload = Grpc_Testing_Payload.with { payload in
            payload.body = Data(repeating: 0, count: Int(responseParameter.size))
          }
        }
        try await writer.write(response)
      }
      return [:]
    }
  }

  /// Server implements `streamingInputCall` which upon half close immediately returns a
  /// `StreamingInputCallResponse` where `aggregatedPayloadSize` is the sum of all request payload
  /// bodies received.
  public func streamingInputCall(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_TestService.Method.StreamingInputCall.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Single<Grpc_Testing_TestService.Method.StreamingInputCall.Output>
  {
    var aggregatedPayloadSize = 0

    for try await message in request.messages {
      aggregatedPayloadSize += message.payload.body.count
    }

    let responseMessage = Grpc_Testing_TestService.Method.StreamingInputCall.Output.with {
      $0.aggregatedPayloadSize = Int32(aggregatedPayloadSize)
    }

    return GRPCCore.ServerResponse.Single(message: responseMessage)
  }

  /// Server implements `fullDuplexCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in each
  /// `StreamingOutputCallRequest`. Each `StreamingOutputCallResponse` should have a payload body
  /// of size `ResponseParameter.size` bytes, as specified by its respective `ResponseParameter`s.
  /// After receiving half close and sending all responses, it closes with OK.
  public func fullDuplexCall(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_TestService.Method.FullDuplexCall.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_TestService.Method.FullDuplexCall.Output>
  {
    return ServerResponse.Stream { writer in
      for try await message in request.messages {
        if message.responseStatus.isInitialized {
          let code = Status.Code(rawValue: Int(message.responseStatus.code))
          let status = Status.init(code: code ?? .unknown, message: message.responseStatus.message)
          if let error = GRPCCore.RPCError(status: status) {
            throw error
          }
        }

        for responseParameter in message.responseParameters {
          let response = Grpc_Testing_StreamingOutputCallResponse.with {
            response in
            response.payload = Grpc_Testing_Payload.with {
              $0.body = Data(count: Int(responseParameter.size))
            }
          }
          try await writer.write(response)
        }
      }
      return [:]
    }
  }

  /// This is not implemented as it is not described in the specification.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
  public func halfDuplexCall(
    request: GRPCCore.ServerRequest.Stream<Grpc_Testing_TestService.Method.HalfDuplexCall.Input>
  ) async throws
    -> GRPCCore.ServerResponse.Stream<Grpc_Testing_TestService.Method.HalfDuplexCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }
}
