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

/// A error thrown by the ``SourceGenerator`` to signal errors in the ``CodeGenerationRequest`` object.
public struct CodeGenError: Error, Hashable, @unchecked Sendable {
  /// The code indicating the domain of the error.
  public var code: Code
  /// A message providing more details about the error which may include details specific to this
  /// instance of the error.
  public var message: String

  /// Creates a new error.
  ///
  /// - Parameters:
  ///   - code: The error code.
  ///   - message: A description of the error.
  ///   - cause: The original error which led to this error being thrown.
  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }

  public static func == (lhs: CodeGenError, rhs: CodeGenError) -> Bool {
    return lhs.code == rhs.code && lhs.message == rhs.message
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.code)
    hasher.combine(self.message)
  }
}

extension CodeGenError {
  public struct Code: Hashable, Sendable {
    private enum Value {
      case sameNameServices
      case sameNameMethods
    }

    private var value: Value
    private init(_ value: Value) {
      self.value = value
    }

    public static var sameNameServices: Self {
      Self(.sameNameServices)
    }

    public static var sameNameMethods: Self {
      Self(.sameNameMethods)
    }
  }
}

extension CodeGenError: CustomStringConvertible {
  public var description: String {
    return "\(self.code): \"\(self.message)\""
  }
}
