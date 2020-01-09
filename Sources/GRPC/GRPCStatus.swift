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
  /// The status code of the RPC.
  public let code: Code
  /// The status message of the RPC.
  public let message: String?

  public init(code: Code, message: String?) {
    self.code = code
    self.message = message
  }

  // Frequently used "default" statuses.

  /// The default status to return for succeeded calls.
  public static let ok = GRPCStatus(code: .ok, message: "OK")
  /// "Internal server error" status.
  public static let processingError = GRPCStatus(code: .internalError, message: "unknown error processing request")
}

extension GRPCStatus: Equatable {
  public static func == (lhs: GRPCStatus, rhs: GRPCStatus) -> Bool {
    return lhs.code == rhs.code && lhs.message == rhs.message
  }
}

extension GRPCStatus: CustomStringConvertible {
  public var description: String {
    if let message = message {
      return "\(code) (\(code.rawValue)): \(message)"
    } else {
      return "\(code) (\(code.rawValue))"
    }
  }
}

extension GRPCStatus {
  /// Status codes for gRPC operations (replicated from `status_code_enum.h` in the
  /// [gRPC core library](https://github.com/grpc/grpc)).
  public enum Code: Int {
    /// Not an error; returned on success.
    case ok = 0

    /// The operation was cancelled (typically by the caller).
    case cancelled = 1

    /// Unknown error. An example of where this error may be returned is if a
    /// Status value received from another address space belongs to an error-space
    /// that is not known in this address space. Also errors raised by APIs that
    /// do not return enough error information may be converted to this error.
    case unknown = 2

    /// Client specified an invalid argument. Note that this differs from
    /// FAILED_PRECONDITION. INVALID_ARGUMENT indicates arguments that are
    /// problematic regardless of the state of the system (e.g., a malformed file
    /// name).
    case invalidArgument = 3

    /// Deadline expired before operation could complete. For operations that
    /// change the state of the system, this error may be returned even if the
    /// operation has completed successfully. For example, a successful response
    /// from a server could have been delayed long enough for the deadline to
    /// expire.
    case deadlineExceeded = 4

    /// Some requested entity (e.g., file or directory) was not found.
    case notFound = 5

    /// Some entity that we attempted to create (e.g., file or directory) already
    /// exists.
    case alreadyExists = 6

    /// The caller does not have permission to execute the specified operation.
    /// PERMISSION_DENIED must not be used for rejections caused by exhausting
    /// some resource (use RESOURCE_EXHAUSTED instead for those errors).
    /// PERMISSION_DENIED must not be used if the caller can not be identified
    /// (use UNAUTHENTICATED instead for those errors).
    case permissionDenied = 7

    /// The request does not have valid authentication credentials for the
    /// operation.
    case unauthenticated = 16

    /// Some resource has been exhausted, perhaps a per-user quota, or perhaps the
    /// entire file system is out of space.
    case resourceExhausted = 8

    /// Operation was rejected because the system is not in a state required for
    /// the operation's execution. For example, directory to be deleted may be
    /// non-empty, an rmdir operation is applied to a non-directory, etc.
    ///
    /// A litmus test that may help a service implementor in deciding
    /// between FAILED_PRECONDITION, ABORTED, and UNAVAILABLE:
    ///  (a) Use UNAVAILABLE if the client can retry just the failing call.
    ///  (b) Use ABORTED if the client should retry at a higher-level
    ///      (e.g., restarting a read-modify-write sequence).
    ///  (c) Use FAILED_PRECONDITION if the client should not retry until
    ///      the system state has been explicitly fixed. E.g., if an "rmdir"
    ///      fails because the directory is non-empty, FAILED_PRECONDITION
    ///      should be returned since the client should not retry unless
    ///      they have first fixed up the directory by deleting files from it.
    ///  (d) Use FAILED_PRECONDITION if the client performs conditional
    ///      REST Get/Update/Delete on a resource and the resource on the
    ///      server does not match the condition. E.g., conflicting
    ///      read-modify-write on the same resource.
    case failedPrecondition = 9

    /// The operation was aborted, typically due to a concurrency issue like
    /// sequencer check failures, transaction aborts, etc.
    ///
    /// See litmus test above for deciding between FAILED_PRECONDITION, ABORTED,
    /// and UNAVAILABLE.
    case aborted = 10

    /// Operation was attempted past the valid range. E.g., seeking or reading
    /// past end of file.
    ///
    /// Unlike INVALID_ARGUMENT, this error indicates a problem that may be fixed
    /// if the system state changes. For example, a 32-bit file system will
    /// generate INVALID_ARGUMENT if asked to read at an offset that is not in the
    /// range [0,2^32-1], but it will generate OUT_OF_RANGE if asked to read from
    /// an offset past the current file size.
    ///
    /// There is a fair bit of overlap between FAILED_PRECONDITION and
    /// OUT_OF_RANGE. We recommend using OUT_OF_RANGE (the more specific error)
    /// when it applies so that callers who are iterating through a space can
    /// easily look for an OUT_OF_RANGE error to detect when they are done.
    case outOfRange = 11

    /// Operation is not implemented or not supported/enabled in this service.
    case unimplemented = 12

    /// Internal errors. Means some invariants expected by underlying System has
    /// been broken. If you see one of these errors, Something is very broken.
    case internalError = 13

    /// The service is currently unavailable. This is a most likely a transient
    /// condition and may be corrected by retrying with a backoff.
    ///
    /// See litmus test above for deciding between FAILED_PRECONDITION, ABORTED,
    /// and UNAVAILABLE.
    case unavailable = 14

    /// Unrecoverable data loss or corruption.
    case dataLoss = 15

    /// Force users to include a default branch:
    case doNotUse = -1
  }
}

/// This protocol serves as a customisation point for error types so that gRPC calls may be
/// terminated with an appropriate status.
public protocol GRPCStatusTransformable: Error {
  /// Make a `GRPCStatus` from the underlying error.
  ///
  /// - Returns: A `GRPCStatus` representing the underlying error.
  func makeGRPCStatus() -> GRPCStatus
}

extension GRPCStatus: GRPCStatusTransformable {
  public func makeGRPCStatus() -> GRPCStatus {
    return self
  }
}

extension NIOHTTP2Errors.StreamClosed: GRPCStatusTransformable {
  public func makeGRPCStatus() -> GRPCStatus {
    return .init(code: .unavailable, message: self.localizedDescription)
  }
}

extension NIOHTTP2Errors.IOOnClosedConnection: GRPCStatusTransformable {
  public func makeGRPCStatus() -> GRPCStatus {
    return .init(code: .unavailable, message: "The connection is closed")
  }
}

extension ChannelError: GRPCStatusTransformable {
  public func makeGRPCStatus() -> GRPCStatus {
    switch self {
    case .inputClosed, .outputClosed, .ioOnClosedChannel:
      return .init(code: .unavailable, message: "The connection is closed")

    default:
      return .processingError
    }
  }
}
