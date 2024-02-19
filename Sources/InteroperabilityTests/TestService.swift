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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
internal struct TestService: Grpc_Testing_TestService.ServiceProtocol {
  internal func unimplementedCall(
    request: ServerRequest.Single<Grpc_Testing_TestService.Method.UnimplementedCall.Input>
  ) async throws
    -> ServerResponse.Single<Grpc_Testing_TestService.Method.UnimplementedCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }

  /// Server implements `emptyCall` which immediately returns the empty message.
  internal func emptyCall(
    request: ServerRequest.Single<Grpc_Testing_TestService.Method.EmptyCall.Input>
  ) async throws -> ServerResponse.Single<Grpc_Testing_TestService.Method.EmptyCall.Output> {
    let message = Grpc_Testing_TestService.Method.EmptyCall.Output()
    return ServerResponse.Single(message: message)
  }

  /// Server implements `unaryCall` which immediately returns a `SimpleResponse` with a payload
  /// body of size `SimpleRequest.responseSize` bytes and type as appropriate for the
  /// `SimpleRequest.responseType`.
  ///
  /// If the server does not support the `responseType`, then it should fail the RPC with
  /// `INVALID_ARGUMENT`.
  internal func unaryCall(
    request: ServerRequest.Single<Grpc_Testing_TestService.Method.UnaryCall.Input>
  ) async throws -> ServerResponse.Single<Grpc_Testing_TestService.Method.UnaryCall.Output> {
    // If the request has a responseStatus set, the server should return that status.
    // If the code is an error code, the server will throw an error containing that code
    // and the message set in the responseStatus.
    // If the code is `ok`, the server will automatically send back an `ok` status.
    if request.message.responseStatus.isInitialized {
      guard let code = Status.Code(rawValue: Int(request.message.responseStatus.code)) else {
        throw RPCError(code: .invalidArgument, message: "The response status code is invalid.")
      }
      let status = Status(
        code: code,
        message: request.message.responseStatus.message
      )
      if let error = RPCError(status: status) {
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
  internal func cacheableUnaryCall(
    request: ServerRequest.Single<Grpc_Testing_TestService.Method.CacheableUnaryCall.Input>
  ) async throws
    -> ServerResponse.Single<Grpc_Testing_TestService.Method.CacheableUnaryCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }

  /// Server implements `streamingOutputCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in `StreamingOutputCallRequest`.
  /// Each `StreamingOutputCallResponse` should have a payload body of size `ResponseParameter.size`
  /// bytes, as specified by its respective `ResponseParameter`. After sending all responses, it
  /// closes with OK.
  internal func streamingOutputCall(
    request: ServerRequest.Single<
      Grpc_Testing_TestService.Method.StreamingOutputCall.Input
    >
  ) async throws
    -> ServerResponse.Stream<Grpc_Testing_TestService.Method.StreamingOutputCall.Output>
  {
    return ServerResponse.Stream { writer in
      for responseParameter in request.message.responseParameters {
        let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
          response.payload = Grpc_Testing_Payload.with { payload in
            payload.body = Data(repeating: 0, count: Int(responseParameter.size))
          }
        }
        try await writer.write(response)
        // We convert the `intervalUs` value from microseconds to nanoseconds.
        try await Task.sleep(nanoseconds: UInt64(responseParameter.intervalUs) * 1000)
      }
      return [:]
    }
  }

  /// Server implements `streamingInputCall` which upon half close immediately returns a
  /// `StreamingInputCallResponse` where `aggregatedPayloadSize` is the sum of all request payload
  /// bodies received.
  internal func streamingInputCall(
    request: ServerRequest.Stream<Grpc_Testing_TestService.Method.StreamingInputCall.Input>
  ) async throws
    -> ServerResponse.Single<Grpc_Testing_TestService.Method.StreamingInputCall.Output>
  {
    var aggregatedPayloadSize = 0

    for try await message in request.messages {
      aggregatedPayloadSize += message.payload.body.count
    }

    let responseMessage = Grpc_Testing_TestService.Method.StreamingInputCall.Output.with {
      $0.aggregatedPayloadSize = Int32(aggregatedPayloadSize)
    }

    return ServerResponse.Single(message: responseMessage)
  }

  /// Server implements `fullDuplexCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in each
  /// `StreamingOutputCallRequest`. Each `StreamingOutputCallResponse` should have a payload body
  /// of size `ResponseParameter.size` bytes, as specified by its respective `ResponseParameter`s.
  /// After receiving half close and sending all responses, it closes with OK.
  internal func fullDuplexCall(
    request: ServerRequest.Stream<Grpc_Testing_TestService.Method.FullDuplexCall.Input>
  ) async throws
    -> ServerResponse.Stream<Grpc_Testing_TestService.Method.FullDuplexCall.Output>
  {
    return ServerResponse.Stream { writer in
      for try await message in request.messages {
        // If a request message has a responseStatus set, the server should return that status.
        // If the code is an error code, the server will throw an error containing that code
        // and the message set in the responseStatus.
        // If the code is `ok`, the server will automatically send back an `ok` status with the response.
        if message.responseStatus.isInitialized {
          guard let code = Status.Code(rawValue: Int(message.responseStatus.code)) else {
            throw RPCError(code: .invalidArgument, message: "The response status code is invalid.")
          }

          let status = Status(code: code, message: message.responseStatus.message)
          if let error = RPCError(status: status) {
            throw error
          }
        }

        for responseParameter in message.responseParameters {
          let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
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
  internal func halfDuplexCall(
    request: ServerRequest.Stream<Grpc_Testing_TestService.Method.HalfDuplexCall.Input>
  ) async throws
    -> ServerResponse.Stream<Grpc_Testing_TestService.Method.HalfDuplexCall.Output>
  {
    throw RPCError(code: .unimplemented, message: "The RPC is not implemented.")
  }
}
