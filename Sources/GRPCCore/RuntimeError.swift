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
@available(gRPCSwift 2.0, *)
public struct RuntimeError: Error, Hashable, Sendable {
  /// The code indicating the domain of the error.
  public var code: Code

  /// A message providing more details about the error which may include details specific to this
  /// instance of the error.
  public var message: String

  /// The original error which led to this error being thrown.
  public var cause: (any Error)?

  /// Creates a new error.
  ///
  /// - Parameters:
  ///   - code: The error code.
  ///   - message: A description of the error.
  ///   - cause: The original error which led to this error being thrown.
  public init(code: Code, message: String, cause: (any Error)? = nil) {
    self.code = code
    self.message = message
    self.cause = cause
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.code)
    hasher.combine(self.message)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.code == rhs.code && lhs.message == rhs.message
  }
}

@available(gRPCSwift 2.0, *)
extension RuntimeError: CustomStringConvertible {
  public var description: String {
    if let cause = self.cause {
      return "\(self.code): \"\(self.message)\" (cause: \"\(cause)\")"
    } else {
      return "\(self.code): \"\(self.message)\""
    }
  }
}

@available(gRPCSwift 2.0, *)
extension RuntimeError {
  public struct Code: Hashable, Sendable {
    private enum Value {
      case invalidArgument
      case serverIsAlreadyRunning
      case serverIsStopped
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

@available(gRPCSwift 2.0, *)
extension RuntimeError.Code: CustomStringConvertible {
  public var description: String {
    String(describing: self.value)
  }
}
