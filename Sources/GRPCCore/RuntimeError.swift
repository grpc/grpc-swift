/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

/// An error thrown at runtime.
///
/// In contrast to ``RPCError``, the ``RuntimeError`` represents errors which happen at a scope
/// wider than an individual RPC. For example, passing invalid configuration values.
public struct RuntimeError: Error, Hashable, @unchecked Sendable {
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

extension RuntimeError: CustomStringConvertible {
  public var description: String {
    if let cause = self.cause {
      return "\(self.code): \"\(self.message)\" (cause: \"\(cause)\")"
    } else {
      return "\(self.code): \"\(self.message)\""
    }
  }
}

extension RuntimeError {
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

extension RuntimeError {
  public struct Code: Hashable, Sendable {
    private enum Value {
      case invalidArgument
      case serverIsAlreadyRunning
      case serverIsStopped
      case failedToStartTransport
      case noTransportsConfigured
      case clientIsAlreadyRunning
      case clientIsStopped
      case transportError
    }

    private var value: Value
    private init(_ value: Value) {
      self.value = value
    }

    /// An argument was invalid.
    public static var invalidArgument: Self {
      Self(.invalidArgument)
    }

    /// At attempt to start the server was made but it is already running.
    public static var serverIsAlreadyRunning: Self {
      Self(.serverIsAlreadyRunning)
    }

    /// At attempt to start the server was made but it has already stopped.
    public static var serverIsStopped: Self {
      Self(.serverIsStopped)
    }

    /// The server couldn't be started because a transport failed to start.
    public static var failedToStartTransport: Self {
      Self(.failedToStartTransport)
    }

    /// The server couldn't be started because no transports were configured.
    public static var noTransportsConfigured: Self {
      Self(.noTransportsConfigured)
    }

    /// At attempt to start the client was made but it is already running.
    public static var clientIsAlreadyRunning: Self {
      Self(.clientIsAlreadyRunning)
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

extension RuntimeError.Code: CustomStringConvertible {
  public var description: String {
    String(describing: self.value)
  }
}
