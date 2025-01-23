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
  /// They will be placed at the top of the generated file. They are already formatted,
  /// meaning they contain  "///" and new lines.
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
  /// request.makeSerializerCodeSnippet = { messageType in
  ///   "ProtobufSerializer<\(messageType)>()"
  /// }
  /// ```
  public var makeSerializerCodeSnippet: (_ messageType: String) -> String

  /// Closure that receives a message type as a `String` and returns a code snippet to
  /// initialize a `MessageDeserializer` for that type as a `String`.
  ///
  /// The result is inserted in the generated code, where clients deserialize RPC outputs and
  /// servers deserialize RPC inputs.
  ///
  /// For example, to serialize Protobuf messages you could specify a serializer as:
  /// ```swift
  /// request.makeDeserializerCodeSnippet = { messageType in
  ///   "ProtobufDeserializer<\(messageType)>()"
  /// }
  /// ```
  public var makeDeserializerCodeSnippet: (_ messageType: String) -> String

  public init(
    fileName: String,
    leadingTrivia: String,
    dependencies: [Dependency],
    services: [ServiceDescriptor],
    makeSerializerCodeSnippet: @escaping (_ messageType: String) -> String,
    makeDeserializerCodeSnippet: @escaping (_ messageType: String) -> String
  ) {
    self.fileName = fileName
    self.leadingTrivia = leadingTrivia
    self.dependencies = dependencies
    self.services = services
    self.makeSerializerCodeSnippet = makeSerializerCodeSnippet
    self.makeDeserializerCodeSnippet = makeDeserializerCodeSnippet
  }
}

extension CodeGenerationRequest {
  @available(*, deprecated, renamed: "makeSerializerSnippet")
  public var lookupSerializer: (_ messageType: String) -> String {
    get { self.makeSerializerCodeSnippet }
    set { self.makeSerializerCodeSnippet = newValue }
  }

  @available(*, deprecated, renamed: "makeDeserializerSnippet")
  public var lookupDeserializer: (_ messageType: String) -> String {
    get { self.makeDeserializerCodeSnippet }
    set { self.makeDeserializerCodeSnippet = newValue }
  }

  @available(
    *,
    deprecated,
    renamed:
      "init(fileName:leadingTrivia:dependencies:services:lookupSerializer:lookupDeserializer:)"
  )
  public init(
    fileName: String,
    leadingTrivia: String,
    dependencies: [Dependency],
    services: [ServiceDescriptor],
    lookupSerializer: @escaping (String) -> String,
    lookupDeserializer: @escaping (String) -> String
  ) {
    self.init(
      fileName: fileName,
      leadingTrivia: leadingTrivia,
      dependencies: dependencies,
      services: services,
      makeSerializerCodeSnippet: lookupSerializer,
      makeDeserializerCodeSnippet: lookupDeserializer
    )
  }
}

/// Represents an import: a module or a specific item from a module.
public struct Dependency: Equatable {
  /// If the dependency is an item, the property's value is the item representation.
  /// If the dependency is a module, this property is nil.
  public var item: Item?

  /// The access level to be included in imports of this dependency.
  public var accessLevel: CodeGenerator.Config.AccessLevel

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
    preconcurrency: PreconcurrencyRequirement = .notRequired,
    accessLevel: CodeGenerator.Config.AccessLevel
  ) {
    self.item = item
    self.module = module
    self.spi = spi
    self.preconcurrency = preconcurrency
    self.accessLevel = accessLevel
  }

  /// Represents an item imported from a module.
  public struct Item: Equatable {
    /// The keyword that specifies the item's kind (e.g. `func`, `struct`).
    public var kind: Kind

    /// The name of the imported item.
    public var name: String

    public init(kind: Kind, name: String) {
      self.kind = kind
      self.name = name
    }

    /// Represents the imported item's kind.
    public struct Kind: Equatable {
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
  public struct PreconcurrencyRequirement: Equatable {
    internal enum Value: Equatable {
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
public struct ServiceDescriptor: Hashable {
  /// Documentation from comments above the IDL service description.
  /// It is already formatted, meaning it contains  "///" and new lines.
  public var documentation: String

  /// The name of the service.
  public var name: ServiceName

  /// A description of each method of a service.
  ///
  /// - SeeAlso: ``MethodDescriptor``.
  public var methods: [MethodDescriptor]

  public init(
    documentation: String,
    name: ServiceName,
    methods: [MethodDescriptor]
  ) {
    self.documentation = documentation
    self.name = name
    self.methods = methods
  }
}

extension ServiceDescriptor {
  @available(*, deprecated, renamed: "init(documentation:name:methods:)")
  public init(
    documentation: String,
    name: Name,
    namespace: Name,
    methods: [MethodDescriptor]
  ) {
    self.documentation = documentation
    self.methods = methods

    let identifier = namespace.base.isEmpty ? name.base : namespace.base + "." + name.base

    let typeName =
      namespace.generatedUpperCase.isEmpty
      ? name.generatedUpperCase
      : namespace.generatedUpperCase + "_" + name.generatedUpperCase

    let propertyName =
      namespace.generatedLowerCase.isEmpty
      ? name.generatedUpperCase
      : namespace.generatedLowerCase + "_" + name.generatedUpperCase

    self.name = ServiceName(
      identifyingName: identifier,
      typeName: typeName,
      propertyName: propertyName
    )
  }
}

/// Represents a method described in an IDL file.
public struct MethodDescriptor: Hashable {
  /// Documentation from comments above the IDL method description.
  /// It is already formatted, meaning it contains  "///" and new lines.
  public var documentation: String

  /// Method name in different formats.
  ///
  /// All properties of this object must be unique for each method
  /// from within a service.
  public var name: MethodName

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
    name: MethodName,
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

extension MethodDescriptor {
  @available(*, deprecated, message: "Use MethodName instead of Name")
  public init(
    documentation: String,
    name: Name,
    isInputStreaming: Bool,
    isOutputStreaming: Bool,
    inputType: String,
    outputType: String
  ) {
    self.documentation = documentation
    self.name = MethodName(
      identifyingName: name.base,
      typeName: name.generatedUpperCase,
      functionName: name.generatedLowerCase
    )
    self.isInputStreaming = isInputStreaming
    self.isOutputStreaming = isOutputStreaming
    self.inputType = inputType
    self.outputType = outputType
  }
}

public struct ServiceName: Hashable {
  /// The identifying name as used in the service/method descriptors including any namespace.
  ///
  /// This value is also used to identify the service to the remote peer, usually as part of the
  /// ":path" pseudoheader if doing gRPC over HTTP/2.
  ///
  /// If the service is declared in package "foo.bar" and the service is called "Baz" then this
  /// value should be "foo.bar.Baz".
  public var identifyingName: String

  /// The name as used on types including any namespace.
  ///
  /// This is used to generate a namespace for each service which contains a number of client and
  /// server protocols and concrete types.
  ///
  /// If the service is declared in package "foo.bar" and the service is called "Baz" then this
  /// value should be "Foo\_Bar\_Baz".
  public var typeName: String

  /// The name as used as a property.
  ///
  /// This is used to provide a convenience getter for a descriptor of the service.
  ///
  /// If the service is declared in package "foo.bar" and the service is called "Baz" then this
  /// value should be "foo\_bar\_Baz".
  public var propertyName: String

  public init(identifyingName: String, typeName: String, propertyName: String) {
    self.identifyingName = identifyingName
    self.typeName = typeName
    self.propertyName = propertyName
  }
}

public struct MethodName: Hashable {
  /// The identifying name as used in the service/method descriptors.
  ///
  /// This value is also used to identify the method to the remote peer, usually as part of the
  /// ":path" pseudoheader if doing gRPC over HTTP/2.
  ///
  /// This value typically starts with an uppercase character, for example "Get".
  public var identifyingName: String

  /// The name as used on types including any namespace.
  ///
  /// This is used to generate a namespace for each method which contains information about
  /// the method.
  ///
  /// This value typically starts with an uppercase character, for example "Get".
  public var typeName: String

  /// The name as used as a property.
  ///
  /// This value typically starts with an lowercase character, for example "get".
  public var functionName: String

  public init(identifyingName: String, typeName: String, functionName: String) {
    self.identifyingName = identifyingName
    self.typeName = typeName
    self.functionName = functionName
  }
}

/// Represents the name associated with a namespace, service or a method, in three different formats.
@available(*, deprecated, message: "Use ServiceName/MethodName instead.")
public struct Name: Hashable {
  /// The base name is the name used for the namespace/service/method in the IDL file, so it should follow
  /// the specific casing of the IDL.
  ///
  /// The base name is also used in the descriptors that identify a specific method or service :
  /// `<service_namespace_baseName>.<service_baseName>.<method_baseName>`.
  public var base: String

  /// The `generatedUpperCase` name is used in the generated code. It is expected
  /// to be the UpperCamelCase version of the base name
  ///
  /// For example, if `base` is "fooBar", then `generatedUpperCase` is "FooBar".
  public var generatedUpperCase: String

  /// The `generatedLowerCase` name is used in the generated code. It is expected
  /// to be the lowerCamelCase version of the base name
  ///
  /// For example, if `base` is "FooBar", then `generatedLowerCase` is "fooBar".
  public var generatedLowerCase: String

  public init(base: String, generatedUpperCase: String, generatedLowerCase: String) {
    self.base = base
    self.generatedUpperCase = generatedUpperCase
    self.generatedLowerCase = generatedLowerCase
  }
}

@available(*, deprecated, message: "Use ServiceName/MethodName instead.")
extension Name {
  /// The base name replacing occurrences of "." with "_".
  ///
  /// For example, if `base` is "Foo.Bar", then `normalizedBase` is "Foo_Bar".
  public var normalizedBase: String {
    return self.base.replacing(".", with: "_")
  }
}
