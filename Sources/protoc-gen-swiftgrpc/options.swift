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

class GeneratorOptions {
  enum Visibility: String {
    case Internal
    case Public

    var sourceSnippet: String {
      switch self {
      case .Internal:
        return "internal"
      case .Public:
        return "public"
      }
    }
  }

  let visibility: Visibility
  let generateTestStubs: Bool
  let generateClient: Bool
  let generateServer: Bool

  init(parameter: String?) throws {
    var visibility: Visibility = .Internal

    var generateTestStubs = false

    for pair in GeneratorOptions.parseParameter(string: parameter) {
      switch pair.key {
      case "Visibility":
        if let value = Visibility(rawValue: pair.value) {
          visibility = value
        } else {
          throw GenerationError.invalidParameterValue(name: pair.key,
                                                      value: pair.value)
        }
      case "TestStubs":
        switch pair.value {
        case "true": generateTestStubs = true
        case "false": generateTestStubs = false
        default: throw GenerationError.invalidParameterValue(name: pair.key,
                                                             value: pair.value)
        }

      default:
        throw GenerationError.unknownParameter(name: pair.key)
      }
    }

    self.visibility = visibility
    self.generateTestStubs = generateTestStubs
    self.generateClient = true
    self.generateServer = true
  }

  static func parseParameter(string: String?) -> [(key: String, value: String)] {
    guard let string = string, string.characters.count > 0 else {
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
      let key = string.substring(to: index)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let value = string.substring(from: string.index(after: index))
        .trimmingCharacters(in: .whitespacesAndNewlines)

      return (key: key, value: value)
    }
    return result
  }
}
