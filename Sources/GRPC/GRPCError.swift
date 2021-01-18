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

/// An error thrown by the gRPC library.
///
/// Implementation details: this is a case-less `enum` with an inner-class per error type. This
/// allows for additional error classes to be added as a SemVer minor change.
///
/// Unfortunately it is not possible to use a private inner `enum` with static property 'cases' on
/// the outer type to mirror each case of the inner `enum` as many of the errors require associated
/// values (pattern matching is not possible).
public enum GRPCError {
  /// The RPC is not implemented on the server.
  public struct RPCNotImplemented: GRPCErrorProtocol {
    /// The path of the RPC which was called, e.g. '/echo.Echo/Get'.
    public var rpc: String

    public init(rpc: String) {
      self.rpc = rpc
    }

    public var description: String {
      return "RPC '\(self.rpc)' is not implemented"
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .unimplemented, message: self.description)
    }
  }

  /// The RPC was cancelled by the client.
  public struct RPCCancelledByClient: GRPCErrorProtocol {
    public let description: String = "RPC was cancelled by the client"

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .cancelled, message: self.description)
    }
  }

  /// The RPC did not complete before the timeout.
  public struct RPCTimedOut: GRPCErrorProtocol {
    /// The time limit which was exceeded by the RPC.
    public var timeLimit: TimeLimit

    public init(_ timeLimit: TimeLimit) {
      self.timeLimit = timeLimit
    }

    public var description: String {
      return "RPC timed out before completing"
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .deadlineExceeded, message: self.description)
    }
  }

  /// A message was not able to be serialized.
  public struct SerializationFailure: GRPCErrorProtocol {
    public let description = "Message serialization failed"

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// A message was not able to be deserialized.
  public struct DeserializationFailure: GRPCErrorProtocol {
    public let description = "Message deserialization failed"

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// It was not possible to compress or decompress a message with zlib.
  public struct ZlibCompressionFailure: GRPCErrorProtocol {
    var code: Int32
    var message: String?

    public init(code: Int32, message: String?) {
      self.code = code
      self.message = message
    }

    public var description: String {
      if let message = self.message {
        return "Zlib error: \(self.code) \(message)"
      } else {
        return "Zlib error: \(self.code)"
      }
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// The decompression limit was exceeded while decompressing a message.
  public struct DecompressionLimitExceeded: GRPCErrorProtocol {
    /// The size of the compressed payload whose decompressed size exceeded the decompression limit.
    public let compressedSize: Int

    public init(compressedSize: Int) {
      self.compressedSize = compressedSize
    }

    public var description: String {
      return "Decompression limit exceeded with \(self.compressedSize) compressed bytes"
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .resourceExhausted, message: nil)
    }
  }

  /// It was not possible to decode a base64 message (gRPC-Web only).
  public struct Base64DecodeError: GRPCErrorProtocol {
    public let description = "Base64 message decoding failed"

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// The compression mechanism used was not supported.
  public struct CompressionUnsupported: GRPCErrorProtocol {
    public let description = "The compression used is not supported"

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .unimplemented, message: self.description)
    }
  }

  /// Too many, or too few, messages were sent over the given stream.
  public struct StreamCardinalityViolation: GRPCErrorProtocol {
    /// The stream on which there was a cardinality violation.
    public let description: String

    /// A request stream cardinality violation.
    public static let request = StreamCardinalityViolation("Request stream cardinality violation")

    /// A response stream cardinality violation.
    public static let response = StreamCardinalityViolation("Response stream cardinality violation")

    private init(_ description: String) {
      self.description = description
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// The 'content-type' HTTP/2 header was missing or not valid.
  public struct InvalidContentType: GRPCErrorProtocol {
    /// The value of the 'content-type' header, if it was present.
    public var contentType: String?

    public init(_ contentType: String?) {
      self.contentType = contentType
    }

    public var description: String {
      if let contentType = self.contentType {
        return "Invalid 'content-type' header: '\(contentType)'"
      } else {
        return "Missing 'content-type' header"
      }
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.description)
    }
  }

  /// The ':status' HTTP/2 header was not "200".
  public struct InvalidHTTPStatus: GRPCErrorProtocol {
    /// The HTTP/2 ':status' header, if it was present.
    public var status: String?

    public init(_ status: String?) {
      self.status = status
    }

    public var description: String {
      if let status = status {
        return "Invalid HTTP response status: \(status)"
      } else {
        return "Missing HTTP ':status' header"
      }
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .init(httpStatus: self.status), message: self.description)
    }
  }

  /// The ':status' HTTP/2 header was not "200" but the 'grpc-status' header was present and valid.
  public struct InvalidHTTPStatusWithGRPCStatus: GRPCErrorProtocol {
    public var status: GRPCStatus

    public init(_ status: GRPCStatus) {
      self.status = status
    }

    public var description: String {
      return "Invalid HTTP response status, but gRPC status was present"
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return self.status
    }
  }

  /// Action was taken after the RPC had already completed.
  public struct AlreadyComplete: GRPCErrorProtocol {
    public var description: String {
      return "The RPC has already completed"
    }

    public init() {}

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .unavailable, message: self.description)
    }
  }

  /// An invalid state has been reached; something has gone very wrong.
  public struct InvalidState: GRPCErrorProtocol {
    public var message: String

    public init(_ message: String) {
      self.message = "Invalid state: \(message)"
    }

    public var description: String {
      return self.message
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.message)
    }
  }

  public struct ProtocolViolation: GRPCErrorProtocol {
    public var message: String

    public init(_ message: String) {
      self.message = "Protocol violation: \(message)"
    }

    public var description: String {
      return self.message
    }

    public func makeGRPCStatus() -> GRPCStatus {
      return GRPCStatus(code: .internalError, message: self.message)
    }
  }
}

extension GRPCError {
  struct WithContext: Error, GRPCStatusTransformable {
    var error: GRPCStatusTransformable
    var file: StaticString
    var line: Int
    var function: StaticString

    init(
      _ error: GRPCStatusTransformable,
      file: StaticString = #file,
      line: Int = #line,
      function: StaticString = #function
    ) {
      self.error = error
      self.file = file
      self.line = line
      self.function = function
    }

    func makeGRPCStatus() -> GRPCStatus {
      return self.error.makeGRPCStatus()
    }
  }
}

/// Requirements for `GRPCError` types.
public protocol GRPCErrorProtocol: GRPCStatusTransformable, Equatable, CustomStringConvertible {}

extension GRPCErrorProtocol {
  /// Creates a `GRPCError.WithContext` containing a `GRPCError` and the location of the call site.
  internal func captureContext(
    file: StaticString = #file,
    line: Int = #line,
    function: StaticString = #function
  ) -> GRPCError.WithContext {
    return GRPCError.WithContext(self, file: file, line: line, function: function)
  }
}

extension GRPCStatus.Code {
  /// The gRPC status code associated with the given HTTP status code. This should only be used if
  /// the RPC did not return a 'grpc-status' trailer.
  internal init(httpStatus: String?) {
    /// See: https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
    switch httpStatus {
    case "400":
      self = .internalError
    case "401":
      self = .unauthenticated
    case "403":
      self = .permissionDenied
    case "404":
      self = .unimplemented
    case "429", "502", "503", "504":
      self = .unavailable
    default:
      self = .unknown
    }
  }
}
