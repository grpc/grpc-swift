/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
#if compiler(>=5.5)
import Foundation
import GRPC
import GRPCInteroperabilityTestModels
import NIOCore

/// An async service provider for the gRPC interoperability test suite.
///
/// See: https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md#server
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public class TestServiceAsyncProvider: Grpc_Testing_TestServiceAsyncProvider {
  public var interceptors: Grpc_Testing_TestServiceServerInterceptorFactoryProtocol?

  public init() {}

  private static let echoMetadataNotImplemented = GRPCStatus(
    code: .unimplemented,
    message: "Echoing metadata is not yet supported"
  )

  /// Features that this server implements.
  ///
  /// Some 'features' are methods, whilst others optionally modify the outcome of those methods. The
  /// specification is not explicit about where these modifying features should be implemented (i.e.
  /// which methods should support them) and they are not listed in the individual method
  /// descriptions. As such implementation of these modifying features within each method is
  /// determined by the features required by each test.
  public static var implementedFeatures: Set<ServerFeature> {
    return [
      .emptyCall,
      .unaryCall,
      .streamingOutputCall,
      .streamingInputCall,
      .fullDuplexCall,
      .echoStatus,
      .compressedResponse,
      .compressedRequest,
    ]
  }

  /// Server implements `emptyCall` which immediately returns the empty message.
  public func emptyCall(
    request: Grpc_Testing_Empty,
    context: GRPCAsyncServerCallContext
  ) async throws -> Grpc_Testing_Empty {
    return Grpc_Testing_Empty()
  }

  /// Server implements `unaryCall` which immediately returns a `SimpleResponse` with a payload
  /// body of size `SimpleRequest.responseSize` bytes and type as appropriate for the
  /// `SimpleRequest.responseType`.
  ///
  /// If the server does not support the `responseType`, then it should fail the RPC with
  /// `INVALID_ARGUMENT`.
  public func unaryCall(
    request: Grpc_Testing_SimpleRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Grpc_Testing_SimpleResponse {
    // We can't validate messages at the wire-encoding layer (i.e. where the compression byte is
    // set), so we have to check via the encoding header. Note that it is possible for the header
    // to be set and for the message to not be compressed.
    if request.expectCompressed.value, !context.requestMetadata.contains(name: "grpc-encoding") {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "Expected compressed request, but 'grpc-encoding' was missing"
      )
    }

    // Should we enable compression? The C++ interoperability client only expects compression if
    // explicitly requested; we'll do the same.
    context.compressionEnabled = request.responseCompressed.value

    if request.shouldEchoStatus {
      let code = GRPCStatus.Code(rawValue: numericCast(request.responseStatus.code)) ?? .unknown
      throw GRPCStatus(code: code, message: request.responseStatus.message)
    }

    if context.requestMetadata.shouldEchoMetadata {
      throw Self.echoMetadataNotImplemented
    }

    if case .UNRECOGNIZED = request.responseType {
      throw GRPCStatus(code: .invalidArgument, message: nil)
    }

    return Grpc_Testing_SimpleResponse.with { response in
      response.payload = Grpc_Testing_Payload.with { payload in
        payload.body = Data(repeating: 0, count: numericCast(request.responseSize))
        payload.type = request.responseType
      }
    }
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
    context: GRPCAsyncServerCallContext
  ) async throws -> Grpc_Testing_SimpleResponse {
    throw GRPCStatus(
      code: .unimplemented,
      message: "'cacheableUnaryCall' requires control of the initial metadata which isn't supported"
    )
  }

  /// Server implements `streamingOutputCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in `StreamingOutputCallRequest`.
  /// Each `StreamingOutputCallResponse` should have a payload body of size `ResponseParameter.size`
  /// bytes, as specified by its respective `ResponseParameter`. After sending all responses, it
  /// closes with OK.
  public func streamingOutputCall(
    request: Grpc_Testing_StreamingOutputCallRequest,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_StreamingOutputCallResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    for responseParameter in request.responseParameters {
      let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
        response.payload = Grpc_Testing_Payload.with { payload in
          payload.body = Data(repeating: 0, count: numericCast(responseParameter.size))
        }
      }

      // Should we enable compression? The C++ interoperability client only expects compression if
      // explicitly requested; we'll do the same.
      let compression: Compression = responseParameter.compressed.value ? .enabled : .disabled
      try await responseStream.send(response, compression: compression)
    }
  }

  /// Server implements `streamingInputCall` which upon half close immediately returns a
  /// `StreamingInputCallResponse` where `aggregatedPayloadSize` is the sum of all request payload
  /// bodies received.
  public func streamingInputCall(
    requestStream: GRPCAsyncRequestStream<Grpc_Testing_StreamingInputCallRequest>,
    context: GRPCAsyncServerCallContext
  ) async throws -> Grpc_Testing_StreamingInputCallResponse {
    var aggregatePayloadSize = 0

    for try await request in requestStream {
      if request.expectCompressed.value {
        guard context.requestMetadata.contains(name: "grpc-encoding") else {
          throw GRPCStatus(
            code: .invalidArgument,
            message: "Expected compressed request, but 'grpc-encoding' was missing"
          )
        }
      }
      aggregatePayloadSize += request.payload.body.count
    }
    return Grpc_Testing_StreamingInputCallResponse.with { response in
      response.aggregatedPayloadSize = numericCast(aggregatePayloadSize)
    }
  }

  /// Server implements `fullDuplexCall` by replying, in order, with one
  /// `StreamingOutputCallResponse` for each `ResponseParameter`s in each
  /// `StreamingOutputCallRequest`. Each `StreamingOutputCallResponse` should have a payload body
  /// of size `ResponseParameter.size` bytes, as specified by its respective `ResponseParameter`s.
  /// After receiving half close and sending all responses, it closes with OK.
  public func fullDuplexCall(
    requestStream: GRPCAsyncRequestStream<Grpc_Testing_StreamingOutputCallRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_StreamingOutputCallResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    // We don't have support for this yet so just fail the call.
    if context.requestMetadata.shouldEchoMetadata {
      throw Self.echoMetadataNotImplemented
    }

    for try await request in requestStream {
      if request.shouldEchoStatus {
        let code = GRPCStatus.Code(rawValue: numericCast(request.responseStatus.code))
        let status = GRPCStatus(code: code ?? .unknown, message: request.responseStatus.message)
        throw status
      } else {
        for responseParameter in request.responseParameters {
          let response = Grpc_Testing_StreamingOutputCallResponse.with { response in
            response.payload = .zeros(count: numericCast(responseParameter.size))
          }
          try await responseStream.send(response)
        }
      }
    }
  }

  /// This is not implemented as it is not described in the specification.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/interop-test-descriptions.md
  public func halfDuplexCall(
    requestStream: GRPCAsyncRequestStream<Grpc_Testing_StreamingOutputCallRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Grpc_Testing_StreamingOutputCallResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws {
    throw GRPCStatus(
      code: .unimplemented,
      message: "'halfDuplexCall' was not described in the specification"
    )
  }
}
#endif // compiler(>=5.5)
