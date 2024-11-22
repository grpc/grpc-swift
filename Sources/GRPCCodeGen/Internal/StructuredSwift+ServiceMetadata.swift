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

extension TypealiasDescription {
  /// `typealias Input = <name>`
  package static func methodInput(
    accessModifier: AccessModifier? = nil,
    name: String
  ) -> Self {
    return TypealiasDescription(
      accessModifier: accessModifier,
      name: "Input",
      existingType: .member(name)
    )
  }

  /// `typealias Output = <name>`
  package static func methodOutput(
    accessModifier: AccessModifier? = nil,
    name: String
  ) -> Self {
    return TypealiasDescription(
      accessModifier: accessModifier,
      name: "Output",
      existingType: .member(name)
    )
  }
}

extension VariableDescription {
  /// ```
  /// static let descriptor = GRPCCore.MethodDescriptor(
  ///   service: GRPCCore.ServiceDescriptor(fullyQualifiedServiceName: "<literalFullyQualifiedService>"),
  ///   method: "<literalMethodName>"
  /// ```
  package static func methodDescriptor(
    accessModifier: AccessModifier? = nil,
    literalFullyQualifiedService: String,
    literalMethodName: String
  ) -> Self {
    return VariableDescription(
      accessModifier: accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifier(.pattern("descriptor")),
      right: .functionCall(
        FunctionCallDescription(
          calledExpression: .identifierType(.methodDescriptor),
          arguments: [
            FunctionArgumentDescription(
              label: "service",
              expression: .functionCall(
                .serviceDescriptor(
                  literalFullyQualifiedService: literalFullyQualifiedService
                )
              )
            ),
            FunctionArgumentDescription(
              label: "method",
              expression: .literal(literalMethodName)
            ),
          ]
        )
      )
    )
  }

  /// ```
  /// static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: <LiteralFullyQualifiedService>)
  /// ```
  package static func serviceDescriptor(
    accessModifier: AccessModifier? = nil,
    literalFullyQualifiedService name: String
  ) -> Self {
    return VariableDescription(
      accessModifier: accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifierPattern("descriptor"),
      right: .functionCall(.serviceDescriptor(literalFullyQualifiedService: name))
    )
  }
}

extension FunctionCallDescription {
  package static func serviceDescriptor(
    literalFullyQualifiedService: String
  ) -> Self {
    FunctionCallDescription(
      calledExpression: .identifier(.type(.serviceDescriptor)),
      arguments: [
        FunctionArgumentDescription(
          label: "fullyQualifiedService",
          expression: .literal(literalFullyQualifiedService)
        )
      ]
    )
  }
}

extension ExtensionDescription {
  /// ```
  /// extension GRPCCore.ServiceDescriptor {
  ///   static let <PropertyName> = Self(
  ///     fullyQualifiedService: <LiteralFullyQualifiedService>
  ///   )
  /// }
  /// ```
  package static func serviceDescriptor(
    accessModifier: AccessModifier? = nil,
    propertyName: String,
    literalFullyQualifiedService: String
  ) -> ExtensionDescription {
    return ExtensionDescription(
      onType: "GRPCCore.ServiceDescriptor",
      declarations: [
        .commentable(
          .doc("Service descriptor for the \"\(literalFullyQualifiedService)\" service."),
          .variable(
            accessModifier: accessModifier,
            isStatic: true,
            kind: .let,
            left: .identifier(.pattern(propertyName)),
            right: .functionCall(
              .serviceDescriptor(literalFullyQualifiedService: literalFullyQualifiedService)
            )
          )
        )
      ]
    )
  }
}

extension VariableDescription {
  /// ```
  /// static let descriptors: [GRPCCore.MethodDescriptor] = [<Name1>.descriptor, ...]
  /// ```
  package static func methodDescriptorsArray(
    accessModifier: AccessModifier? = nil,
    methodNamespaceNames names: [String]
  ) -> Self {
    return VariableDescription(
      accessModifier: accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifier(.pattern("descriptors")),
      type: .array(.methodDescriptor),
      right: .literal(.array(names.map { name in .identifierPattern(name).dot("descriptor") }))
    )
  }
}

extension EnumDescription {
  /// ```
  /// enum <Method> {
  ///   typealias Input = <InputType>
  ///   typealias Output = <OutputType>
  ///   static let descriptor = GRPCCore.MethodDescriptor(
  ///     service: <ServiceNamespace>.descriptor.fullyQualifiedService,
  ///     method: "<LiteralMethod>"
  ///   )
  /// }
  /// ```
  package static func methodNamespace(
    accessModifier: AccessModifier? = nil,
    name: String,
    literalMethod: String,
    literalFullyQualifiedService: String,
    inputType: String,
    outputType: String
  ) -> Self {
    return EnumDescription(
      accessModifier: accessModifier,
      name: name,
      members: [
        .commentable(
          .doc("Request type for \"\(literalMethod)\"."),
          .typealias(.methodInput(accessModifier: accessModifier, name: inputType))
        ),
        .commentable(
          .doc("Response type for \"\(literalMethod)\"."),
          .typealias(.methodOutput(accessModifier: accessModifier, name: outputType))
        ),
        .commentable(
          .doc("Descriptor for \"\(literalMethod)\"."),
          .variable(
            .methodDescriptor(
              accessModifier: accessModifier,
              literalFullyQualifiedService: literalFullyQualifiedService,
              literalMethodName: literalMethod
            )
          )
        ),
      ]
    )
  }

  /// ```
  /// enum Method {
  ///   enum <Method> {
  ///     typealias Input = <MethodInput>
  ///     typealias Output = <MethodOutput>
  ///     static let descriptor = GRPCCore.MethodDescriptor(
  ///       service: <serviceNamespaceName>.descriptor.fullyQualifiedService,
  ///       method: "<Method>"
  ///     )
  ///   }
  ///   ...
  ///   static let descriptors: [GRPCCore.MethodDescriptor] = [
  ///     <Method>.descriptor,
  ///     ...
  ///   ]
  /// }
  /// ```
  package static func methodsNamespace(
    accessModifier: AccessModifier? = nil,
    literalFullyQualifiedService: String,
    methods: [MethodDescriptor]
  ) -> EnumDescription {
    var description = EnumDescription(accessModifier: accessModifier, name: "Method")

    // Add a namespace for each method.
    let methodNamespaces: [Declaration] = methods.map { method in
      return .commentable(
        .doc("Namespace for \"\(method.name.base)\" metadata."),
        .enum(
          .methodNamespace(
            accessModifier: accessModifier,
            name: method.name.base,
            literalMethod: method.name.base,
            literalFullyQualifiedService: literalFullyQualifiedService,
            inputType: method.inputType,
            outputType: method.outputType
          )
        )
      )
    }
    description.members.append(contentsOf: methodNamespaces)

    // Add an array of method descriptors
    let methodDescriptorsArray: VariableDescription = .methodDescriptorsArray(
      accessModifier: accessModifier,
      methodNamespaceNames: methods.map { $0.name.base }
    )
    description.members.append(
      .commentable(
        .doc("Descriptors for all methods in the \"\(literalFullyQualifiedService)\" service."),
        .variable(methodDescriptorsArray)
      )
    )

    return description
  }

  /// ```
  /// enum <Name> {
  ///   static let descriptor = GRPCCore.ServiceDescriptor.<namespacedServicePropertyName>
  ///   enum Method {
  ///     ...
  ///   }
  /// }
  /// ```
  package static func serviceNamespace(
    accessModifier: AccessModifier? = nil,
    name: String,
    literalFullyQualifiedService: String,
    methods: [MethodDescriptor]
  ) -> EnumDescription {
    var description = EnumDescription(accessModifier: accessModifier, name: name)

    // static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "...")
    let descriptor = VariableDescription.serviceDescriptor(
      accessModifier: accessModifier,
      literalFullyQualifiedService: literalFullyQualifiedService
    )
    description.members.append(
      .commentable(
        .doc("Service descriptor for the \"\(literalFullyQualifiedService)\" service."),
        .variable(descriptor)
      )
    )

    // enum Method { ... }
    let methodsNamespace: EnumDescription = .methodsNamespace(
      accessModifier: accessModifier,
      literalFullyQualifiedService: literalFullyQualifiedService,
      methods: methods
    )
    description.members.append(
      .commentable(
        .doc("Namespace for method metadata."),
        .enum(methodsNamespace)
      )
    )

    return description
  }
}

extension [CodeBlock] {
  /// ```
  /// enum <Service> {
  ///   ...
  /// }
  ///
  /// extension GRPCCore.ServiceDescriptor {
  ///   ...
  /// }
  /// ```
  package static func serviceMetadata(
    accessModifier: AccessModifier? = nil,
    service: ServiceDescriptor
  ) -> Self {
    var blocks: [CodeBlock] = []

    let serviceNamespace: EnumDescription = .serviceNamespace(
      accessModifier: accessModifier,
      name: service.namespacedGeneratedName,
      literalFullyQualifiedService: service.fullyQualifiedName,
      methods: service.methods
    )
    blocks.append(
      CodeBlock(
        comment: .doc(
          "Namespace containing generated types for the \"\(service.fullyQualifiedName)\" service."
        ),
        item: .declaration(.enum(serviceNamespace))
      )
    )

    let descriptorExtension: ExtensionDescription = .serviceDescriptor(
      accessModifier: accessModifier,
      propertyName: service.namespacedServicePropertyName,
      literalFullyQualifiedService: service.fullyQualifiedName
    )
    blocks.append(CodeBlock(item: .declaration(.extension(descriptorExtension))))

    return blocks
  }
}
