import Foundation
import NIOHTTP1

/// Encapsulates the result of a gRPC call.
public struct GRPCStatus: Error, Equatable {
  /// The code to return in the `grpc-status` header.
  public let code: StatusCode
  /// The message to return in the `grpc-message` header.
  public let message: String?
  /// Additional HTTP headers to return in the trailers.
  public let trailingMetadata: HTTPHeaders

  public init(code: StatusCode, message: String?, trailingMetadata: HTTPHeaders = HTTPHeaders()) {
    self.code = code
    self.message = message
    self.trailingMetadata = trailingMetadata
  }

  // Frequently used "default" statuses.

  /// The default status to return for succeeded calls.
  public static let ok = GRPCStatus(code: .ok, message: "OK")
  /// "Internal server error" status.
  public static let processingError = GRPCStatus(code: .internalError, message: "unknown error processing request")
}

public protocol GRPCStatusTransformable: Error {
  func asGRPCStatus() -> GRPCStatus
}

extension GRPCStatus: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    return self
  }
}
