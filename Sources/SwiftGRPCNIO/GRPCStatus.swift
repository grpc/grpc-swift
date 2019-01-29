import Foundation
import NIOHTTP1

/// Encapsulates the result of a gRPC call.
public struct GRPCStatus: Error {
  /// The code to return in the `grpc-status` header.
  public let code: StatusCode
  /// The message to return in the `grpc-message` header.
  public let message: String
  /// Additional HTTP headers to return in the trailers.
  public let trailingMetadata: HTTPHeaders

  public init(code: StatusCode, message: String, trailingMetadata: HTTPHeaders = HTTPHeaders()) {
    self.code = code
    self.message = message
    self.trailingMetadata = trailingMetadata
  }

  // Frequently used "default" statuses.
  
  /// The default status to return for succeeded calls.
  public static let ok = GRPCStatus(code: .ok, message: "OK")
  /// "Internal server error" status.
  public static let processingError = GRPCStatus(code: .internalError, message: "unknown error processing request")

  /// Status indicating that the given method is not implemented.
  public static func unimplemented(method: String) -> GRPCStatus {
    return GRPCStatus(code: .unimplemented, message: "unknown method " + method)
  }

  // These status codes are informed by: https://github.com/grpc/grpc/blob/master/doc/statuscodes.md
  static internal let requestProtoParseError = GRPCStatus(code: .internalError, message: "could not parse request proto")
  static internal let responseProtoSerializationError = GRPCStatus(code: .internalError, message: "could not serialize response proto")
  static internal let unsupportedCompression = GRPCStatus(code: .unimplemented, message: "compression is not supported on the server")
}

protocol GRPCStatusTransformable: Error {
  func asGRPCStatus() -> GRPCStatus
}

extension GRPCStatus: GRPCStatusTransformable {
  func asGRPCStatus() -> GRPCStatus {
    return self
  }
}
