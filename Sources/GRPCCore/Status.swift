/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

/// A status object represents the outcome of an RPC.
///
/// Each ``Status`` is composed of a ``Status/code-swift.property`` and ``Status/message``. Each
/// service implementation chooses the code and message returned to the client for each RPC
/// it implements. However, client and server implementations may also generate status objects
/// on their own if an error happens.
///
/// ``Status`` represents the raw outcome of an RPC whether it was successful or not; ``RPCError``
/// is similar to ``Status`` but only represents error cases, in other words represents all status
/// codes apart from ``Code-swift.struct/ok``.
public struct Status: @unchecked Sendable, Hashable {
  // @unchecked because it relies on heap allocated storage and 'isKnownUniquelyReferenced'

  private var storage: Storage
  private mutating func ensureStorageIsUnique() {
    if !isKnownUniquelyReferenced(&self.storage) {
      self.storage = self.storage.copy()
    }
  }

  /// A code representing the high-level domain of the status.
  public var code: Code {
    get { self.storage.code }
    set {
      self.ensureStorageIsUnique()
      self.storage.code = newValue
    }
  }

  /// A message providing additional context about the status.
  public var message: String {
    get { self.storage.message }
    set {
      self.ensureStorageIsUnique()
      self.storage.message = newValue
    }
  }

  /// Create a new status.
  ///
  /// - Parameters:
  ///   - code: The status code.
  ///   - message: A message providing additional context about the code.
  public init(code: Code, message: String) {
    if code == .ok, message.isEmpty {
      // Avoid a heap allocation for the common case.
      self.storage = Storage.okWithNoMessage
    } else {
      self.storage = Storage(code: code, message: message)
    }
  }
}

extension Status: CustomStringConvertible {
  public var description: String {
    "\(self.code): \"\(self.message)\""
  }
}

extension Status {
  private final class Storage: Hashable {
    static let okWithNoMessage = Storage(code: .ok, message: "")

    var code: Status.Code
    var message: String

    init(code: Status.Code, message: String) {
      self.code = code
      self.message = message
    }

    func copy() -> Self {
      Self(code: self.code, message: self.message)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.code)
      hasher.combine(self.message)
    }

    static func == (lhs: Status.Storage, rhs: Status.Storage) -> Bool {
      return lhs.code == rhs.code && lhs.message == rhs.message
    }
  }
}

extension Status {
  /// Status codes for gRPC operations.
  ///
  /// The outcome of every RPC is indicated by a status code.
  public struct Code: Hashable, CustomStringConvertible, Sendable {
    // Source: https://github.com/grpc/grpc/blob/master/doc/statuscodes.md
    enum Wrapped: UInt8, Hashable, Sendable {
      case ok = 0
      case cancelled = 1
      case unknown = 2
      case invalidArgument = 3
      case deadlineExceeded = 4
      case notFound = 5
      case alreadyExists = 6
      case permissionDenied = 7
      case resourceExhausted = 8
      case failedPrecondition = 9
      case aborted = 10
      case outOfRange = 11
      case unimplemented = 12
      case internalError = 13
      case unavailable = 14
      case dataLoss = 15
      case unauthenticated = 16
    }

    /// The underlying value.
    let wrapped: Wrapped

    /// The numeric value of the error code.
    public var rawValue: Int { Int(self.wrapped.rawValue) }

    /// Creates a status codes from its raw value.
    ///
    /// - Parameters:
    ///   - rawValue: The numeric value to create the code from.
    /// Returns `nil` if the `rawValue` isn't a valid error code.
    public init?(rawValue: Int) {
      if let value = UInt8(exactly: rawValue), let wrapped = Wrapped(rawValue: value) {
        self.wrapped = wrapped
      } else {
        return nil
      }
    }

    /// Creates a status code from an ``RPCError/Code-swift.struct``.
    ///
    /// - Parameters:
    ///   - code: The error code to create this ``Status/Code-swift.struct`` from.
    public init(_ code: RPCError.Code) {
      self.wrapped = code.wrapped
    }

    private init(code: Wrapped) {
      self.wrapped = code
    }

    public var description: String {
      String(describing: self.wrapped)
    }
  }
}

extension Status.Code {
  /// The operation completed successfully.
  public static let ok = Self(code: .ok)

  /// The operation was cancelled (typically by the caller).
  public static let cancelled = Self(code: .cancelled)

  /// Unknown error. An example of where this error may be returned is if a
  /// Status value received from another address space belongs to an error-space
  /// that is not known in this address space. Also errors raised by APIs that
  /// do not return enough error information may be converted to this error.
  public static let unknown = Self(code: .unknown)

  /// Client specified an invalid argument. Note that this differs from
  /// ``failedPrecondition``. ``invalidArgument`` indicates arguments that are
  /// problematic regardless of the state of the system (e.g., a malformed file
  /// name).
  public static let invalidArgument = Self(code: .invalidArgument)

  /// Deadline expired before operation could complete. For operations that
  /// change the state of the system, this error may be returned even if the
  /// operation has completed successfully. For example, a successful response
  /// from a server could have been delayed long enough for the deadline to
  /// expire.
  public static let deadlineExceeded = Self(code: .deadlineExceeded)

  /// Some requested entity (e.g., file or directory) was not found.
  public static let notFound = Self(code: .notFound)

  /// Some entity that we attempted to create (e.g., file or directory) already
  /// exists.
  public static let alreadyExists = Self(code: .alreadyExists)

  /// The caller does not have permission to execute the specified operation.
  /// ``permissionDenied`` must not be used for rejections caused by exhausting
  /// some resource (use ``resourceExhausted`` instead for those errors).
  /// ``permissionDenied`` must not be used if the caller can not be identified
  /// (use ``unauthenticated`` instead for those errors).
  public static let permissionDenied = Self(code: .permissionDenied)

  /// Some resource has been exhausted, perhaps a per-user quota, or perhaps the
  /// entire file system is out of space.
  public static let resourceExhausted = Self(code: .resourceExhausted)

  /// Operation was rejected because the system is not in a state required for
  /// the operation's execution. For example, directory to be deleted may be
  /// non-empty, an rmdir operation is applied to a non-directory, etc.
  ///
  /// A litmus test that may help a service implementor in deciding
  /// between ``failedPrecondition``, ``aborted``, and ``unavailable``:
  /// - Use ``unavailable`` if the client can retry just the failing call.
  /// - Use ``aborted`` if the client should retry at a higher-level
  ///   (e.g., restarting a read-modify-write sequence).
  /// - Use ``failedPrecondition`` if the client should not retry until
  ///   the system state has been explicitly fixed. E.g., if an "rmdir"
  ///   fails because the directory is non-empty, ``failedPrecondition``
  ///   should be returned since the client should not retry unless
  ///   they have first fixed up the directory by deleting files from it.
  /// - Use ``failedPrecondition`` if the client performs conditional
  ///   REST Get/Update/Delete on a resource and the resource on the
  ///   server does not match the condition. E.g., conflicting
  ///   read-modify-write on the same resource.
  public static let failedPrecondition = Self(code: .failedPrecondition)

  /// The operation was aborted, typically due to a concurrency issue like
  /// sequencer check failures, transaction aborts, etc.
  ///
  /// See litmus test above for deciding between ``failedPrecondition``, ``aborted``,
  /// and ``unavailable``.
  public static let aborted = Self(code: .aborted)

  /// Operation was attempted past the valid range. E.g., seeking or reading
  /// past end of file.
  ///
  /// Unlike ``invalidArgument``, this error indicates a problem that may be fixed
  /// if the system state changes. For example, a 32-bit file system will
  /// generate ``invalidArgument`` if asked to read at an offset that is not in the
  /// range [0,2^32-1], but it will generate ``outOfRange`` if asked to read from
  /// an offset past the current file size.
  ///
  /// There is a fair bit of overlap between ``failedPrecondition`` and
  /// ``outOfRange``. We recommend using ``outOfRange`` (the more specific error)
  /// when it applies so that callers who are iterating through a space can
  /// easily look for an ``outOfRange`` error to detect when they are done.
  public static let outOfRange = Self(code: .outOfRange)

  /// Operation is not implemented or not supported/enabled in this service.
  public static let unimplemented = Self(code: .unimplemented)

  /// Internal errors. Means some invariants expected by underlying System has
  /// been broken. If you see one of these errors, Something is very broken.
  public static let internalError = Self(code: .internalError)

  /// The service is currently unavailable. This is a most likely a transient
  /// condition and may be corrected by retrying with a backoff.
  ///
  /// See litmus test above for deciding between ``failedPrecondition``, ``aborted``,
  /// and ``unavailable``.
  public static let unavailable = Self(code: .unavailable)

  /// Unrecoverable data loss or corruption.
  public static let dataLoss = Self(code: .dataLoss)

  /// The request does not have valid authentication credentials for the
  /// operation.
  public static let unauthenticated = Self(code: .unauthenticated)
}
