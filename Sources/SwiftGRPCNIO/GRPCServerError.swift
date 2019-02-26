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

public enum GRPCServerError: Error, Equatable {
  /// The RPC method is not implemented on the server.
  case unimplementedMethod(String)

  /// It was not possible to decode a base64 message (gRPC-Web only).
  case base64DecodeError

  /// It was not possible to parse the request protobuf.
  case requestProtoParseFailure

  /// It was not possible to serialize the response protobuf.
  case responseProtoSerializationFailure

  /// The given compression mechanism is not supported.
  case unsupportedCompressionMechanism(String)

  /// Compression was indicated in the gRPC message, but not for the call.
  case unexpectedCompression

  /// More than one request was sent for a unary-request call.
  case requestCardinalityViolation

  /// The server received a message when it was not in a writable state.
  case serverNotWritable

  /// An invalid state has been reached; something has gone very wrong.
  case invalidState(String)
}

extension GRPCServerError: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    // These status codes are informed by: https://github.com/grpc/grpc/blob/master/doc/statuscodes.md
    switch self {
    case .unimplementedMethod(let method):
      return GRPCStatus(code: .unimplemented, message: "unknown method \(method)")

    case .base64DecodeError:
      return GRPCStatus(code: .internalError, message: "could not decode base64 message")

    case .requestProtoParseFailure:
      return GRPCStatus(code: .internalError, message: "could not parse request proto")

    case .responseProtoSerializationFailure:
      return GRPCStatus(code: .internalError, message: "could not serialize response proto")

    case .unsupportedCompressionMechanism(let mechanism):
      return GRPCStatus(code: .unimplemented, message: "unsupported compression mechanism \(mechanism)")

    case .unexpectedCompression:
      return GRPCStatus(code: .unimplemented, message: "compression was enabled for this gRPC message but not for this call")

    case .requestCardinalityViolation:
      return GRPCStatus(code: .unimplemented, message: "request cardinality violation; method requires exactly one request but client sent more")

    case .serverNotWritable, .invalidState:
      return GRPCStatus.processingError
    }
  }
}
