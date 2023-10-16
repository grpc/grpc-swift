/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import SwiftProtobufPluginLibrary

enum GenerationError: Error {
  /// Raised when parsing the parameter string and found an unknown key
  case unknownParameter(name: String)
  /// Raised when a parameter was giving an invalid value
  case invalidParameterValue(name: String, value: String)
  /// Raised to wrap another error but provide a context message.
  case wrappedError(message: String, error: Error)

  var localizedDescription: String {
    switch self {
    case let .unknownParameter(name):
      return "Unknown generation parameter '\(name)'"
    case let .invalidParameterValue(name, value):
      return "Unknown value for generation parameter '\(name)': '\(value)'"
    case let .wrappedError(message, error):
      return "\(message): \(error.localizedDescription)"
    }
  }
}

final class GeneratorOptions {
  enum Visibility: String {
    case `internal` = "Internal"
    case `public` = "Public"
    case `package` = "Package"

    var sourceSnippet: String {
      switch self {
      case .internal:
        return "internal"
      case .public:
        return "public"
      case .package:
        return "package"
      }
    }
  }

  private(set) var visibility = Visibility.internal

  private(set) var generateServer = true

  private(set) var generateClient = true
  private(set) var generateTestClient = false

  private(set) var keepMethodCasing = false
  private(set) var protoToModuleMappings = ProtoFileToModuleMappings()
  private(set) var fileNaming = FileNaming.FullPath
  private(set) var extraModuleImports: [String] = []
  private(set) var gRPCModuleName = "GRPC"
  private(set) var swiftProtobufModuleName = "SwiftProtobuf"
  private(set) var generateReflectionData = false

  init(parameter: String?) throws {
    for pair in GeneratorOptions.parseParameter(string: parameter) {
      switch pair.key {
      case "Visibility":
        if let value = Visibility(rawValue: pair.value) {
          self.visibility = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "Server":
        if let value = Bool(pair.value) {
          self.generateServer = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "Client":
        if let value = Bool(pair.value) {
          self.generateClient = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "TestClient":
        if let value = Bool(pair.value) {
          self.generateTestClient = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "KeepMethodCasing":
        if let value = Bool(pair.value) {
          self.keepMethodCasing = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "ProtoPathModuleMappings":
        if !pair.value.isEmpty {
          do {
            self.protoToModuleMappings = try ProtoFileToModuleMappings(path: pair.value)
          } catch let e {
            throw GenerationError.wrappedError(
              message: "Parameter 'ProtoPathModuleMappings=\(pair.value)'",
              error: e
            )
          }
        }

      case "FileNaming":
        if let value = FileNaming(rawValue: pair.value) {
          self.fileNaming = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "ExtraModuleImports":
        if !pair.value.isEmpty {
          self.extraModuleImports.append(pair.value)
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "GRPCModuleName":
        if !pair.value.isEmpty {
          self.gRPCModuleName = pair.value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "SwiftProtobufModuleName":
        if !pair.value.isEmpty {
          self.swiftProtobufModuleName = pair.value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "ReflectionData":
        if let value = Bool(pair.value) {
          self.generateReflectionData = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      default:
        throw GenerationError.unknownParameter(name: pair.key)
      }
    }
  }

  static func parseParameter(string: String?) -> [(key: String, value: String)] {
    guard let string = string, !string.isEmpty else {
      return []
    }
    let parts = string.components(separatedBy: ",")

    // Partitions the string into the section before the = and after the =
    let result = parts.map { string -> (key: String, value: String) in

      // Finds the equal sign and exits early if none
      guard let index = string.range(of: "=")?.lowerBound else {
        return (string, "")
      }

      // Creates key/value pair and trims whitespace
      let key = string[..<index]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let value = string[string.index(after: index)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)

      return (key: key, value: value)
    }
    return result
  }
}
