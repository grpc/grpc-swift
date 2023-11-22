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

/// Describes the services, dependencies and trivia from an IDL file,
/// and the IDL itself through its specific serializer and deserializer.
public struct CodeGenerationRequest {
  /// The name of the source file containing the IDL. It contains the file's extension.
  var fileName: String

  /// The Swift imports that the generated file should depend on.
  ///
  /// - SeeAlso: ``Dependency``.
  var dependencies: [Dependency] = []

  /// Any comments at the top of the file including documentation and copyright headers.
  var leadingTrivia: String

  /// An array of service descriptors.
  ///
  /// - SeeAlso: ``ServiceDescriptor``.
  var services: [ServiceDescriptor] = []

  /// Closure that receives the message type and returns a string representation of the
  /// serializer call for that message type. The result is inserted in the string representing
  /// the generated code, where clients or servers serialize their output.
  ///
  /// For example: `lookupSerializer: {"ProtobufSerializer<\($0)>()"}`.
  var lookupSerializer: (String) -> String

  /// Closure that receives the message type and returns a string representation of the
  /// deserializer call for that message type. The result is inserted in the string representing
  /// the generated code, where clients or servers deserialize their input.
  ///
  /// For example: `lookupDeserializer: {"ProtobufDeserializer<\($0)>()"}`.
  var lookupDeserializer: (String) -> String

  /// Represents an import: a module or a specific item from a module.
  public struct Dependency {
    /// If the dependency is an item, the property's value is the item representation.
    /// If the dependency is a module, this property is nil.
    var item: Item? = nil

    /// The name of the imported module or of the module an item is imported from.
    var module: String

    /// Represents an item imported from a module.
    public struct Item {
      /// The keyword that specifies the item's kind (e.g.  `func`, `struct`).
      var kind: Kind

      /// The imported item's symbol / name.
      var name: String

      /// Represents the imported item's kind.
      public struct Kind {
        /// One of the possible keywords associated to the imported item's kind.
        var keyword: Keyword

        public init(_ keyword: Keyword) {
          self.keyword = keyword
        }

        internal enum Keyword {
          case `typealias`
          case `struct`
          case `class`
          case `enum`
          case `protocol`
          case `let`
          case `var`
          case `func`
        }
      }
    }
  }

  /// Represents a service described in an IDL file.
  struct ServiceDescriptor {
    /// Documentation from comments above the IDL service description.
    var documentation: String

    /// Service name.
    var name: String

    /// Array of descriptors for the methods of a service.
    ///
    /// - SeeAlso: ``MethodDescriptor``.
    var methods: [MethodDescriptor] = []

    /// Represents a method described in an IDL file.
    struct MethodDescriptor {
      /// Documentation from comments above the IDL method description.
      var documentation: String

      /// Method name.
      var name: String

      /// Identifies if the method is input streaming.
      var isInputStreaming: Bool

      /// Identifies if the method is output streaming.
      var isOutputStreaming: Bool

      /// The generated input type for the described method.
      var inputType: String

      /// The generated output type for the described method.
      var ouputType: String
    }
  }
}
