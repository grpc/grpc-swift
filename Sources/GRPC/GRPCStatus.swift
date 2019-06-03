import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2

/// Encapsulates the result of a gRPC call.
///
/// We use a `class` here for a couple of reasons:
/// - The size of the equivalent `struct` is larger than the value buffer in an existential
///   container so would incur a heap allocation each time a `GRPCStatus` is passed to a function
///   taking an `Error`.
/// - We aren't using value semantics (since all properties are constant).
public final class GRPCStatus: Error {
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

extension NIOHTTP2Errors.StreamClosed: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    return .init(code: .unavailable, message: self.localizedDescription)
  }
}

extension NIOHTTP2Errors.IOOnClosedConnection: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    return .init(code: .unavailable, message: "The connection is closed")
  }
}

extension ChannelError: GRPCStatusTransformable {
  public func asGRPCStatus() -> GRPCStatus {
    switch self {
    case .inputClosed, .outputClosed, .ioOnClosedChannel:
      return .init(code: .unavailable, message: "The connection is closed")

    default:
      return .processingError
    }
  }
}
