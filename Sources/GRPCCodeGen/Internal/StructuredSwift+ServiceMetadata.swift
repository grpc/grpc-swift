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
  ///   service: <serviceNamespace>.descriptor.fullyQualifiedService,
  ///   method: "<literalMethodName>"
  /// ```
  package static func methodDescriptor(
    accessModifier: AccessModifier? = nil,
    serviceNamespace: String,
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
              expression: .identifierType(
                .member([serviceNamespace, "descriptor"])
              ).dot("fullyQualifiedService")
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
  /// static let descriptor = GRPCCore.ServiceDescriptor.<namespacedProperty>
  /// ```
  package static func serviceDescriptor(
    accessModifier: AccessModifier? = nil,
    namespacedProperty: String
  ) -> Self {
    return VariableDescription(
      accessModifier: accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifierPattern("descriptor"),
      right: .identifier(.type(.serviceDescriptor)).dot(namespacedProperty)
    )
  }
}

extension ExtensionDescription {
  /// ```
  /// extension GRPCCore.ServiceDescriptor {
  ///   static let <PropertyName> = Self(
  ///     package: "<LiteralNamespaceName>",
  ///     service: "<LiteralServiceName>"
  ///   )
  /// }
  /// ```
  package static func serviceDescriptor(
    accessModifier: AccessModifier? = nil,
    propertyName: String,
    literalNamespace: String,
    literalService: String
  ) -> ExtensionDescription {
    return ExtensionDescription(
      onType: "GRPCCore.ServiceDescriptor",
      declarations: [
        .variable(
          accessModifier: accessModifier,
          isStatic: true,
          kind: .let,
          left: .identifier(.pattern(propertyName)),
          right: .functionCall(
            calledExpression: .identifierType(.member("Self")),
            arguments: [
              FunctionArgumentDescription(
                label: "package",
                expression: .literal(literalNamespace)
              ),
              FunctionArgumentDescription(
                label: "service",
                expression: .literal(literalService)
              ),
            ]
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
    serviceNamespace: String,
    inputType: String,
    outputType: String
  ) -> Self {
    return EnumDescription(
      accessModifier: accessModifier,
      name: name,
      members: [
        .typealias(.methodInput(accessModifier: accessModifier, name: inputType)),
        .typealias(.methodOutput(accessModifier: accessModifier, name: outputType)),
        .variable(
          .methodDescriptor(
            accessModifier: accessModifier,
            serviceNamespace: serviceNamespace,
            literalMethodName: literalMethod
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
    serviceNamespace: String,
    methods: [MethodDescriptor]
  ) -> EnumDescription {
    var description = EnumDescription(accessModifier: accessModifier, name: "Method")

    // Add a namespace for each method.
    let methodNamespaces: [Declaration] = methods.map { method in
      return .enum(
        .methodNamespace(
          accessModifier: accessModifier,
          name: method.name.base,
          literalMethod: method.name.base,
          serviceNamespace: serviceNamespace,
          inputType: method.inputType,
          outputType: method.outputType
        )
      )
    }
    description.members.append(contentsOf: methodNamespaces)

    // Add an array of method descriptors
    let methodDescriptorsArray: VariableDescription = .methodDescriptorsArray(
      accessModifier: accessModifier,
      methodNamespaceNames: methods.map { $0.name.base }
    )
    description.members.append(.variable(methodDescriptorsArray))

    return description
  }

  /// ```
  /// enum <Name> {
  ///   static let descriptor = GRPCCore.ServiceDescriptor.<namespacedServicePropertyName>
  ///   enum Method {
  ///     ...
  ///   }
  ///   @available(...)
  ///   typealias StreamingServiceProtocol = ...
  ///   @available(...)
  ///   typealias ServiceProtocol = ...
  ///   ...
  /// }
  /// ```
  package static func serviceNamespace(
    accessModifier: AccessModifier? = nil,
    name: String,
    serviceDescriptorProperty: String,
    client: Bool,
    server: Bool,
    methods: [MethodDescriptor]
  ) -> EnumDescription {
    var description = EnumDescription(accessModifier: accessModifier, name: name)

    // static let descriptor = GRPCCore.ServiceDescriptor.<namespacedServicePropertyName>
    let descriptor = VariableDescription.serviceDescriptor(
      accessModifier: accessModifier,
      namespacedProperty: serviceDescriptorProperty
    )
    description.members.append(.variable(descriptor))

    // enum Method { ... }
    let methodsNamespace: EnumDescription = .methodsNamespace(
      accessModifier: accessModifier,
      serviceNamespace: name,
      methods: methods
    )
    description.members.append(.enum(methodsNamespace))

    // Typealiases for the various protocols.
    var typealiasNames: [String] = []
    if server {
      typealiasNames.append("StreamingServiceProtocol")
      typealiasNames.append("ServiceProtocol")
    }
    if client {
      typealiasNames.append("ClientProtocol")
      typealiasNames.append("Client")
    }
    let typealiases: [Declaration] = typealiasNames.map { alias in
      .typealias(
        accessModifier: accessModifier,
        name: alias,
        existingType: .member(name + "_" + alias)
      )
    }
    description.members.append(contentsOf: typealiases)

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
    service: ServiceDescriptor,
    client: Bool,
    server: Bool
  ) -> Self {
    var blocks: [CodeBlock] = []

    let serviceNamespace: EnumDescription = .serviceNamespace(
      accessModifier: accessModifier,
      name: service.namespacedGeneratedName,
      serviceDescriptorProperty: service.namespacedServicePropertyName,
      client: client,
      server: server,
      methods: service.methods
    )
    blocks.append(CodeBlock(item: .declaration(.enum(serviceNamespace))))

    let descriptorExtension: ExtensionDescription = .serviceDescriptor(
      accessModifier: accessModifier,
      propertyName: service.namespacedServicePropertyName,
      literalNamespace: service.namespace.base,
      literalService: service.name.base
    )
    blocks.append(CodeBlock(item: .declaration(.extension(descriptorExtension))))

    return blocks
  }
}
