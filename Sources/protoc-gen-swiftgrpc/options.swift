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

enum GenerationError: Error {
  /// Raised when parsing the parameter string and found an unknown key
  case unknownParameter(name: String)
  /// Raised when a parameter was giving an invalid value
  case invalidParameterValue(name: String, value: String)

  var localizedDescription: String {
    switch self {
    case .unknownParameter(let name):
      return "Unknown generation parameter '\(name)'"
    case .invalidParameterValue(let name, let value):
      return "Unknown value for generation parameter '\(name)': '\(value)'"
    }
  }
}

final class GeneratorOptions {
  enum Visibility: String {
    case `internal` = "Internal"
    case `public` = "Public"

    var sourceSnippet: String {
      switch self {
      case .internal:
        return "internal"
      case .public:
        return "public"
      }
    }
  }

  private(set) var visibility = Visibility.internal
  private(set) var generateServer = true
  private(set) var generateClient = true
  private(set) var generateAsynchronous = true
  private(set) var generateSynchronous = true
  private(set) var generateTestStubs = false

  init(parameter: String?) throws {
    for pair in GeneratorOptions.parseParameter(string: parameter) {
      switch pair.key {
      case "Visibility":
        if let value = Visibility(rawValue: pair.value) {
          visibility = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "Server":
        if let value = Bool(pair.value) {
          generateServer = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "Client":
        if let value = Bool(pair.value) {
          generateClient = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }
        
      case "Async":
        if let value = Bool(pair.value) {
          generateAsynchronous = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }
        
      case "Sync":
        if let value = Bool(pair.value) {
          generateSynchronous = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key, value: pair.value)
        }

      case "TestStubs":
        if let value = Bool(pair.value) {
            generateTestStubs = value
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
