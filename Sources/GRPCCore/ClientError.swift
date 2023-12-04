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

/// A runtime error thrown by the client.
///
/// In contrast to ``RPCError``, the ``ClientError`` represents errors which happen at a scope
/// wider than an individual RPC. For example, attempting to start a client which is already
/// stopped would result in a ``ClientError``.
public struct ClientError: Error, Hashable, @unchecked Sendable {
  private var storage: Storage

  // Ensures the underlying storage is unique.
  private mutating func ensureUniqueStorage() {
    if !isKnownUniquelyReferenced(&self.storage) {
      self.storage = self.storage.copy()
    }
  }

  /// The code indicating the domain of the error.
  public var code: Code {
    get { self.storage.code }
    set {
      self.ensureUniqueStorage()
      self.storage.code = newValue
    }
  }

  /// A message providing more details about the error which may include details specific to this
  /// instance of the error.
  public var message: String {
    get { self.storage.message }
    set {
      self.ensureUniqueStorage()
      self.storage.message = newValue
    }
  }

  /// The original error which led to this error being thrown.
  public var cause: Error? {
    get { self.storage.cause }
    set {
      self.ensureUniqueStorage()
      self.storage.cause = newValue
    }
  }

  /// Creates a new error.
  ///
  /// - Parameters:
  ///   - code: The error code.
  ///   - message: A description of the error.
  ///   - cause: The original error which led to this error being thrown.
  public init(code: Code, message: String, cause: Error? = nil) {
    self.storage = Storage(code: code, message: message, cause: cause)
  }
}

extension ClientError: CustomStringConvertible {
  public var description: String {
    if let cause = self.cause {
      return "\(self.code): \"\(self.message)\" (cause: \"\(cause)\")"
    } else {
      return "\(self.code): \"\(self.message)\""
    }
  }
}

extension ClientError {
  private final class Storage: Hashable {
    var code: Code
    var message: String
    var cause: Error?

    init(code: Code, message: String, cause: Error?) {
      self.code = code
      self.message = message
      self.cause = cause
    }

    func copy() -> Storage {
      return Storage(code: self.code, message: self.message, cause: self.cause)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.code)
      hasher.combine(self.message)
    }

    static func == (lhs: Storage, rhs: Storage) -> Bool {
      return lhs.code == rhs.code && lhs.message == rhs.message
    }
  }
}

extension ClientError {
  public struct Code: Hashable, Sendable {
    private enum Value {
      case clientIsAlreadyRunning
      case clientIsNotRunning
      case clientIsStopped
      case transportError
    }

    private var value: Value
    private init(_ value: Value) {
      self.value = value
    }

    /// At attempt to start the client was made but it is already running.
    public static var clientIsAlreadyRunning: Self {
      Self(.clientIsAlreadyRunning)
    }

    /// An attempt to start an RPC was made but the client is not running.
    public static var clientIsNotRunning: Self {
      Self(.clientIsNotRunning)
    }

    /// At attempt to start the client was made but it has already stopped.
    public static var clientIsStopped: Self {
      Self(.clientIsStopped)
    }

    /// The transport threw an error whilst connected.
    public static var transportError: Self {
      Self(.transportError)
    }
  }
}

extension ClientError.Code: CustomStringConvertible {
  public var description: String {
    String(describing: self.value)
  }
}
