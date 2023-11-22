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

import Foundation

/// Describes the services, dependencies and trivia from an IDL file,
/// and the IDL itself through its specific serializer and deserializer.
struct CodeGenerationRequest {
  /// The name of the source file containing the IDL.
  var fileName: String

  /// The swift imports that this file depends on.
  var dependencies: [Dependency]?

  /// Any comments at the top of the file including
  /// documentation and copyright headers.
  var leadingTrivia: String

  /// An array of service descriptors.
  var services: [ServiceDescriptor]

  /// String representation of the serializer call.
  var lookupSerializer: (String) -> String

  /// String representation of the deserializer call.
  var lookupDeserializer: (String) -> String

  /// Represents an import: a module or a specific item from a module.
  struct Dependency {
    /// Represents an item imported from a module.
    struct Symbol {
      enum Kind: String {
        case `typealias` = "typealias"
        case `struct` = "struct"
        case `class` = "class"
        case `enum` = "enum"
        case `protocol` = "protocol"
        case `let` = "let"
        case `var` = "var"
        case `func` = "func"
      }

      var kind: Kind
      var name: String
    }
    var symbol: Symbol?
    var module: String
  }

  /// Represents a service described in an IDL file.
  struct ServiceDescriptor {
    /// Description of the service from comments
    /// above the description from the IDL file.
    var docs: String

    var name: String

    /// Array of descriptors for the methods of a service.
    var methods: [MethodDescriptor]

    /// Represents a method described in an IDL file.
    struct MethodDescriptor {
      var name: String
      var isInputStreaming: Bool
      var isOutputStreaming: Bool
      var inputType: String
      var ouputType: String
      var docs: String
    }
  }
}
