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
public struct CodeGenError: Error, Hashable, Sendable {
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
  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }
}

extension CodeGenError {
  public struct Code: Hashable, Sendable {
    private enum Value {
      case nonUniqueServiceName
      case nonUniqueMethodName
    }

    private var value: Value
    private init(_ value: Value) {
      self.value = value
    }

    /// The same name is used for two services that are either in the same namespace or don't have a namespace.
    public static var nonUniqueServiceName: Self {
      Self(.nonUniqueServiceName)
    }

    /// The same name is used for two methods of the same service.
    public static var nonUniqueMethodName: Self {
      Self(.nonUniqueMethodName)
    }
  }
}

extension CodeGenError: CustomStringConvertible {
  public var description: String {
    return "\(self.code): \"\(self.message)\""
  }
}
