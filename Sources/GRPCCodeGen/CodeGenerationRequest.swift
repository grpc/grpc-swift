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
  /// The name of the source file containing the IDL, including the extension if applicable.
  public var fileName: String

  /// Any comments at the top of the file such as documentation and copyright headers.
  /// They will be placed at the top of the generated file.
  public var leadingTrivia: String

  /// The Swift imports that the generated file depends on. The gRPC specific imports aren't required
  /// as they will be added by default in the generated file.
  ///
  /// - SeeAlso: ``Dependency``.
  public var dependencies: [Dependency]

  /// A description of each service to generate.
  ///
  /// - SeeAlso: ``ServiceDescriptor``.
  public var services: [ServiceDescriptor]

  /// Closure that receives a message type as a `String` and returns a code snippet to
  /// initialise a `MessageSerializer` for that type as a `String`.
  ///
  /// The result is inserted in the generated code, where clients serialize RPC inputs and
  /// servers serialize RPC outputs.
  ///
  /// For example, to serialize Protobuf messages you could specify a serializer as:
  /// ```swift
  /// request.lookupSerializer = { messageType in
  ///   "ProtobufSerializer<\(messageType)>()"
  /// }
  /// ```
  public var lookupSerializer: (_ messageType: String) -> String

  /// Closure that receives a message type as a `String` and returns a code snippet to
  /// initialize a `MessageDeserializer` for that type as a `String`.
  ///
  /// The result is inserted in the generated code, where clients deserialize RPC outputs and
  /// servers deserialize RPC inputs.
  ///
  /// For example, to serialize Protobuf messages you could specify a serializer as:
  /// ```swift
  /// request.lookupDeserializer = { messageType in
  ///   "ProtobufDeserializer<\(messageType)>()"
  /// }
  /// ```
  public var lookupDeserializer: (_ messageType: String) -> String

  public init(
    fileName: String,
    leadingTrivia: String,
    dependencies: [Dependency],
    services: [ServiceDescriptor],
    lookupSerializer: @escaping (String) -> String,
    lookupDeserializer: @escaping (String) -> String
  ) {
    self.fileName = fileName
    self.leadingTrivia = leadingTrivia
    self.dependencies = dependencies
    self.services = services
    self.lookupSerializer = lookupSerializer
    self.lookupDeserializer = lookupDeserializer
  }

  /// Represents an import: a module or a specific item from a module.
  public struct Dependency {
    /// If the dependency is an item, the property's value is the item representation.
    /// If the dependency is a module, this property is nil.
    public var item: Item? = nil

    /// The name of the imported module or of the module an item is imported from.
    public var module: String

    /// The name of the private interface for an `@_spi` import.
    ///
    /// For example, if `spi` was "Secret" and the module name was "Foo" then the import
    /// would be `@_spi(Secret) import Foo`.
    public var spi: String?

    /// Requirements for the `@preconcurrency` attribute.
    public var preconcurrency: PreconcurrencyRequirement

    public init(
      item: Item? = nil,
      module: String,
      spi: String? = nil,
      preconcurrency: PreconcurrencyRequirement = .notRequired
    ) {
      self.item = item
      self.module = module
      self.spi = spi
      self.preconcurrency = preconcurrency
    }

    /// Represents an item imported from a module.
    public struct Item {
      /// The keyword that specifies the item's kind (e.g. `func`, `struct`).
      public var kind: Kind

      /// The name of the imported item.
      public var name: String

      public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
      }

      /// Represents the imported item's kind.
      public struct Kind {
        /// Describes the keyword associated with the imported item.
        internal enum Value: String {
          case `typealias`
          case `struct`
          case `class`
          case `enum`
          case `protocol`
          case `let`
          case `var`
          case `func`
        }

        internal var value: Value

        internal init(_ value: Value) {
          self.value = value
        }

        /// The imported item is a typealias.
        public static var `typealias`: Self {
          Self(.`typealias`)
        }

        /// The imported item is a struct.
        public static var `struct`: Self {
          Self(.`struct`)
        }

        /// The imported item is a class.
        public static var `class`: Self {
          Self(.`class`)
        }

        /// The imported item is an enum.
        public static var `enum`: Self {
          Self(.`enum`)
        }

        /// The imported item is a protocol.
        public static var `protocol`: Self {
          Self(.`protocol`)
        }

        /// The imported item is a let.
        public static var `let`: Self {
          Self(.`let`)
        }

        /// The imported item is a var.
        public static var `var`: Self {
          Self(.`var`)
        }

        /// The imported item is a function.
        public static var `func`: Self {
          Self(.`func`)
        }
      }
    }

    /// Describes any requirement for the `@preconcurrency` attribute.
    public struct PreconcurrencyRequirement {
      internal enum Value {
        case required
        case notRequired
        case requiredOnOS([String])
      }

      internal var value: Value

      internal init(_ value: Value) {
        self.value = value
      }

      /// The attribute is always required.
      public static var required: Self {
        Self(.required)
      }

      /// The attribute is not required.
      public static var notRequired: Self {
        Self(.notRequired)
      }

      /// The attribute is required only on the named operating systems.
      public static func requiredOnOS(_ OSs: [String]) -> PreconcurrencyRequirement {
        return Self(.requiredOnOS(OSs))
      }
    }
  }

  /// Represents a service described in an IDL file.
  public struct ServiceDescriptor {
    /// Documentation from comments above the IDL service description.
    public var documentation: String

    /// Service name.
    public var name: String

    /// The service namespace.
    ///
    /// For `.proto` files it is the package name.
    public var namespace: String

    /// A description of each method of a service.
    ///
    /// - SeeAlso: ``MethodDescriptor``.
    public var methods: [MethodDescriptor]

    public init(
      documentation: String,
      name: String,
      namespace: String,
      methods: [MethodDescriptor]
    ) {
      self.documentation = documentation
      self.name = name
      self.namespace = namespace
      self.methods = methods
    }

    /// Represents a method described in an IDL file.
    public struct MethodDescriptor {
      /// Documentation from comments above the IDL method description.
      public var documentation: String

      /// Method name.
      public var name: String

      /// Identifies if the method is input streaming.
      public var isInputStreaming: Bool

      /// Identifies if the method is output streaming.
      public var isOutputStreaming: Bool

      /// The generated input type for the described method.
      public var inputType: String

      /// The generated output type for the described method.
      public var outputType: String

      public init(
        documentation: String,
        name: String,
        isInputStreaming: Bool,
        isOutputStreaming: Bool,
        inputType: String,
        outputType: String
      ) {
        self.documentation = documentation
        self.name = name
        self.isInputStreaming = isInputStreaming
        self.isOutputStreaming = isOutputStreaming
        self.inputType = inputType
        self.outputType = outputType
      }
    }
  }
}
