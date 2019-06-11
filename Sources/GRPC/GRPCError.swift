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
import NIOHTTP1

/// Wraps a gRPC error to provide contextual information about where it was thrown.
public struct GRPCError: Error, GRPCStatusTransformable {
  public enum Origin { case client, server }

  /// The underlying error thrown by framework.
  public let wrappedError: Error

  /// The origin of the error.
  public let origin: Origin

  /// The file in which the error was thrown.
  public let file: StaticString

  /// The line number in the `file` where the error was thrown.
  public let line: Int

  public func asGRPCStatus() -> GRPCStatus {
    return (wrappedError as? GRPCStatusTransformable)?.asGRPCStatus() ?? .processingError
  }

  private init(_ error: Error, origin: Origin, file: StaticString, line: Int) {
    self.wrappedError = error
    self.origin = origin
    self.file = file
    self.line = line
  }

  /// Creates a `GRPCError` which may only be thrown from the client.
  public static func client(_ error: GRPCClientError, file: StaticString = #file, line: Int = #line) -> GRPCError {
    return GRPCError(error, origin: .client, file: file, line: line)
  }

  /// Creates a `GRPCError` which was thrown from the client.
  public static func client(_ error: GRPCCommonError, file: StaticString = #file, line: Int = #line) -> GRPCError {
    return GRPCError(error, origin: .client, file: file, line: line)
  }

  /// Creates a `GRPCError` which may only be thrown from the server.
  public static func server(_ error: GRPCServerError, file: StaticString = #file, line: Int = #line) -> GRPCError {
    return GRPCError(error, origin: .server, file: file, line: line)
  }

  /// Creates a `GRPCError` which was thrown from the server.
  public static func server(_ error: GRPCCommonError, file: StaticString = #file, line: Int = #line) -> GRPCError {
    return GRPCError(error, origin: .server, file: file, line: line)
  }

  /// Creates a `GRPCError` which was may be thrown by either the server or the client.
  public static func common(_ error: GRPCCommonError, origin: Origin, file: StaticString = #file, line: Int = #line) -> GRPCError {
    return GRPCError(error, origin: origin, file: file, line: line)
  }

  public static func unknown(_ error: Error, origin: Origin) -> GRPCError {
    return GRPCError(error, origin: origin, file: "<unknown>", line: 0)
  }
}

/// An error which should only be thrown by the server.
public enum GRPCServerError: Error, Equatable {
  /// The RPC method is not implemented on the server.
  case unimplementedMethod(String)

  /// It was not possible to decode a base64 message (gRPC-Web only).
  case base64DecodeError

  /// It was not possible to deserialize the request protobuf.
  case requestProtoDeserializationFailure

  /// It was not possible to serialize the response protobuf.
  case responseProtoSerializationFailure

  /// Zero requests were sent for a unary-request call.
  case noRequestsButOneExpected
  
  /// More than one request was sent for a unary-request call.
  case tooManyRequests

  /// The server received a message when it was not in a writable state.
  case serverNotWritable
}

/// An error which should only be thrown by the client.
public enum GRPCClientError: Error, Equatable {
  /// The response status was not "200 OK".
  case HTTPStatusNotOk(HTTPResponseStatus)

  /// The call was cancelled by the client.
  case cancelledByClient

  /// It was not possible to deserialize the response protobuf.
  case responseProtoDeserializationFailure

  /// It was not possible to serialize the request protobuf.
  case requestProtoSerializationFailure

  /// More than one response was received for a unary-response call.
  case responseCardinalityViolation

  /// The call deadline was exceeded.
  case deadlineExceeded(GRPCTimeout)

  /// The protocol negotiated via ALPN was not valid.
  case applicationLevelProtocolNegotiationFailed
}

/// An error which should be thrown by either the client or server.
public enum GRPCCommonError: Error, Equatable {
  /// An invalid state has been reached; something has gone very wrong.
  case invalidState(String)

  /// Compression was indicated in the "grpc-message-encoding" header but not in the gRPC message compression flag, or vice versa.
  case unexpectedCompression

  /// The given compression mechanism is not supported.
  case unsupportedCompressionMechanism(String)
}

extension GRPCServerError: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    // These status codes are informed by: https://github.com/grpc/grpc/blob/master/doc/statuscodes.md
    switch self {
    case .unimplementedMethod(let method):
      return GRPCStatus(code: .unimplemented, message: "unknown method \(method)")

    case .base64DecodeError:
      return GRPCStatus(code: .internalError, message: "could not decode base64 message")

    case .requestProtoDeserializationFailure:
      return GRPCStatus(code: .internalError, message: "could not parse request proto")

    case .responseProtoSerializationFailure:
      return GRPCStatus(code: .internalError, message: "could not serialize response proto")

    case .noRequestsButOneExpected:
      return GRPCStatus(code: .unimplemented, message: "request cardinality violation; method requires exactly one request but client sent none")
      
    case .tooManyRequests:
      return GRPCStatus(code: .unimplemented, message: "request cardinality violation; method requires exactly one request but client sent more")

    case .serverNotWritable:
      return GRPCStatus.processingError
    }
  }
}

extension GRPCClientError: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    switch self {
    case .HTTPStatusNotOk(let status):
      return GRPCStatus(code: status.grpcStatusCode, message: "\(status.code): \(status.reasonPhrase)")

    case .cancelledByClient:
      return GRPCStatus(code: .cancelled, message: "client cancelled the call")

    case .responseCardinalityViolation:
      return GRPCStatus(code: .unimplemented, message: "response cardinality violation; method requires exactly one response but server sent more")

    case .responseProtoDeserializationFailure:
      return GRPCStatus(code: .internalError, message: "could not parse response proto")

    case .requestProtoSerializationFailure:
      return GRPCStatus(code: .internalError, message: "could not serialize request proto")

    case .deadlineExceeded(let timeout):
      return GRPCStatus(code: .deadlineExceeded, message: "call exceeded timeout of \(timeout)")

    case .applicationLevelProtocolNegotiationFailed:
      return GRPCStatus(code: .invalidArgument, message: "failed to negotiate application level protocol")
    }
  }
}

extension GRPCCommonError: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    switch self {
    case .invalidState:
      return GRPCStatus.processingError

    case .unexpectedCompression:
      return GRPCStatus(code: .unimplemented, message: "compression was enabled for this gRPC message but not for this call")

    case .unsupportedCompressionMechanism(let mechanism):
      return GRPCStatus(code: .unimplemented, message: "unsupported compression mechanism \(mechanism)")
    }
  }
}

extension HTTPResponseStatus {
  /// The gRPC status code associated with the HTTP status code.
  ///
  /// See: https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
  internal var grpcStatusCode: GRPCStatus.Code {
    switch self {
      case .badRequest:
        return .internalError
      case .unauthorized:
        return .unauthenticated
      case .forbidden:
        return .permissionDenied
      case .notFound:
        return .unimplemented
      case .tooManyRequests, .badGateway, .serviceUnavailable, .gatewayTimeout:
        return .unavailable
      default:
        return .unknown
    }
  }
}
