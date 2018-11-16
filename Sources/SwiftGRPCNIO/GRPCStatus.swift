import Foundation
import NIOHTTP1

// Encapsulates the result of a gRPC call.
public struct GRPCStatus: Error {
  // The code to return in the `grpc-status` header.
  public let code: StatusCode
  // The message to return in the `grpc-message` header.
  public let message: String
  // Additional HTTP headers to return in the trailers.
  public let trailingMetadata: HTTPHeaders

  public init(code: StatusCode, message: String, trailingMetadata: HTTPHeaders = HTTPHeaders()) {
    self.code = code
    self.message = message
    self.trailingMetadata = trailingMetadata
  }

  // Frequently used "default" statuses.
  public static let ok = GRPCStatus(code: .ok, message: "OK")
  public static let processingError = GRPCStatus(code: .internalError, message: "unknown error processing request")

  public static func unimplemented(method: String) -> GRPCStatus {
    return GRPCStatus(code: .unimplemented, message: "unknown method " + method)
  }
}
