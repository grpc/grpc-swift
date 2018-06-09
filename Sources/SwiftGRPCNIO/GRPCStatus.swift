import Foundation
import NIOHTTP1

public struct GRPCStatus: Error {
  public let code: StatusCode
  public let message: String
  public let trailingMetadata: HTTPHeaders

  public init(code: StatusCode, message: String, trailingMetadata: HTTPHeaders = HTTPHeaders()) {
    self.code = code
    self.message = message
    self.trailingMetadata = trailingMetadata
  }

  public static let ok = GRPCStatus(code: .ok, message: "OK")
  public static let processingError = GRPCStatus(code: .internalError, message: "unknown error processing request")

  public static func unimplemented(method: String) -> GRPCStatus {
    return GRPCStatus(code: .unimplemented, message: "unknown method " + method)
  }
}
