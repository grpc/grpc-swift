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

/// Creates enums containing useful type aliases and static properties for the methods, services and
/// namespaces described in a ``CodeGenerationRequest`` object, using types from
/// ``StructuredSwiftRepresentation``.
///
/// For example, in the case of the ``Echo`` service, the ``TypealiasTranslator`` will create
/// a representation for the following generated code:
/// ```swift
/// public enum Echo_Echo {
///   public static let descriptor = ServiceDescriptor.echo_Echo
///
///   public enum Method {
///     public enum Get {
///       public typealias Input = Echo_EchoRequest
///       public typealias Output = Echo_EchoResponse
///       public static let descriptor = MethodDescriptor(
///         service: Echo_Echo.descriptor.fullyQualifiedService,
///         method: "Get"
///       )
///     }
///
///     public enum Collect {
///       public typealias Input = Echo_EchoRequest
///       public typealias Output = Echo_EchoResponse
///       public static let descriptor = MethodDescriptor(
///         service: Echo_Echo.descriptor.fullyQualifiedService,
///         method: "Collect"
///       )
///     }
///     // ...
///
///     public static let descriptors: [MethodDescriptor] = [
///       Get.descriptor,
///       Collect.descriptor,
///       // ...
///     ]
///   }
///
///   @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
///   public typealias StreamingServiceProtocol = Echo_EchoServiceStreamingProtocol
///   @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
///   public typealias ServiceProtocol = Echo_EchoServiceProtocol
///
/// }
///
/// extension ServiceDescriptor {
///   public static let echo_Echo = Self(
///     package: "echo",
///     service: "Echo"
///   )
/// }
/// ```
///
/// A ``CodeGenerationRequest`` can contain multiple namespaces, so the TypealiasTranslator will create a ``CodeBlock``
/// for each namespace.
struct TypealiasTranslator: SpecializedTranslator {
  let client: Bool
  let server: Bool
  let accessLevel: SourceGenerator.Configuration.AccessLevel

  init(client: Bool, server: Bool, accessLevel: SourceGenerator.Configuration.AccessLevel) {
    self.client = client
    self.server = server
    self.accessLevel = accessLevel
  }

  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    var codeBlocks = [CodeBlock]()
    let services = codeGenerationRequest.services
    let servicesByEnumName = Dictionary(
      grouping: services,
      by: { $0.namespacedGeneratedName }
    )

    // Sorting the keys of the dictionary is necessary so that the generated enums are deterministically ordered.
    for (generatedEnumName, services) in servicesByEnumName.sorted(by: { $0.key < $1.key }) {
      for service in services {
        codeBlocks.append(
          CodeBlock(
            item: .declaration(try self.makeServiceEnum(from: service, named: generatedEnumName))
          )
        )

        codeBlocks.append(
          CodeBlock(item: .declaration(self.makeServiceDescriptorExtension(for: service)))
        )
      }
    }

    return codeBlocks
  }
}

extension TypealiasTranslator {
  private func makeServiceEnum(
    from service: CodeGenerationRequest.ServiceDescriptor,
    named name: String
  ) throws -> Declaration {
    var serviceEnum = EnumDescription(
      accessModifier: self.accessModifier,
      name: name
    )
    var methodsEnum = EnumDescription(accessModifier: self.accessModifier, name: "Method")
    let methods = service.methods

    // Create the method specific enums.
    for method in methods {
      let methodEnum = self.makeMethodEnum(from: method, in: service)
      methodsEnum.members.append(methodEnum)
    }

    // Create the method descriptor array.
    let methodDescriptorsDeclaration = self.makeMethodDescriptors(for: service)
    methodsEnum.members.append(methodDescriptorsDeclaration)

    // Create the static service descriptor property.
    let staticServiceDescriptorProperty = self.makeStaticServiceDescriptorProperty(for: service)

    serviceEnum.members.append(.variable(staticServiceDescriptorProperty))
    serviceEnum.members.append(.enum(methodsEnum))

    if self.server {
      // Create the streaming and non-streaming service protocol type aliases.
      let serviceProtocols = self.makeServiceProtocolsTypealiases(for: service)
      serviceEnum.members.append(contentsOf: serviceProtocols)
    }

    if self.client {
      // Create the client protocol type alias.
      let clientProtocol = self.makeClientProtocolTypealias(for: service)
      serviceEnum.members.append(clientProtocol)

      // Create type alias for Client struct.
      let clientStruct = self.makeClientStructTypealias(for: service)
      serviceEnum.members.append(clientStruct)
    }

    return .enum(serviceEnum)
  }

  private func makeMethodEnum(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var methodEnum = EnumDescription(name: method.name.generatedUpperCase)

    let inputTypealias = Declaration.typealias(
      accessModifier: self.accessModifier,
      name: "Input",
      existingType: .member([method.inputType])
    )
    let outputTypealias = Declaration.typealias(
      accessModifier: self.accessModifier,
      name: "Output",
      existingType: .member([method.outputType])
    )
    let descriptorVariable = self.makeMethodDescriptor(
      from: method,
      in: service
    )
    methodEnum.members.append(inputTypealias)
    methodEnum.members.append(outputTypealias)
    methodEnum.members.append(descriptorVariable)

    methodEnum.accessModifier = self.accessModifier

    return .enum(methodEnum)
  }

  private func makeMethodDescriptor(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let fullyQualifiedService = MemberAccessDescription(
      left: .memberAccess(
        MemberAccessDescription(
          left: .identifierType(.member([service.namespacedGeneratedName])),
          right: "descriptor"
        )
      ),
      right: "fullyQualifiedService"
    )

    let descriptorDeclarationLeft = Expression.identifier(.pattern("descriptor"))
    let descriptorDeclarationRight = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member("MethodDescriptor")),
        arguments: [
          FunctionArgumentDescription(
            label: "service",
            expression: .memberAccess(fullyQualifiedService)
          ),
          FunctionArgumentDescription(
            label: "method",
            expression: .literal(method.name.base)
          ),
        ]
      )
    )

    return .variable(
      accessModifier: self.accessModifier,
      isStatic: true,
      kind: .let,
      left: descriptorDeclarationLeft,
      right: descriptorDeclarationRight
    )
  }

  private func makeMethodDescriptors(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var methodDescriptors = [Expression]()
    let methodNames = service.methods.map { $0.name.generatedUpperCase }

    for methodName in methodNames {
      let methodDescriptorPath = Expression.memberAccess(
        MemberAccessDescription(
          left: .identifierType(
            .member([methodName])
          ),
          right: "descriptor"
        )
      )
      methodDescriptors.append(methodDescriptorPath)
    }

    return .variable(
      accessModifier: self.accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifier(.pattern("descriptors")),
      type: .array(.member("MethodDescriptor")),
      right: .literal(.array(methodDescriptors))
    )
  }

  private func makeServiceProtocolsTypealiases(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> [Declaration] {
    let streamingServiceProtocolTypealias = Declaration.typealias(
      accessModifier: self.accessModifier,
      name: "StreamingServiceProtocol",
      existingType: .member("\(service.namespacedGeneratedName)StreamingServiceProtocol")
    )
    let serviceProtocolTypealias = Declaration.typealias(
      accessModifier: self.accessModifier,
      name: "ServiceProtocol",
      existingType: .member("\(service.namespacedGeneratedName)ServiceProtocol")
    )

    return [
      .guarded(
        self.availabilityGuard,
        streamingServiceProtocolTypealias
      ),
      .guarded(
        self.availabilityGuard,
        serviceProtocolTypealias
      ),
    ]
  }

  private func makeClientProtocolTypealias(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    return .guarded(
      self.availabilityGuard,
      .typealias(
        accessModifier: self.accessModifier,
        name: "ClientProtocol",
        existingType: .member("\(service.namespacedGeneratedName)ClientProtocol")
      )
    )
  }

  private func makeClientStructTypealias(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    return .guarded(
      self.availabilityGuard,
      .typealias(
        accessModifier: self.accessModifier,
        name: "Client",
        existingType: .member("\(service.namespacedGeneratedName)Client")
      )
    )
  }

  private func makeServiceIdentifier(_ service: CodeGenerationRequest.ServiceDescriptor) -> String {
    let prefix: String

    if service.namespace.normalizedBase.isEmpty {
      prefix = ""
    } else {
      prefix = service.namespace.normalizedBase + "_"
    }

    return prefix + service.name.normalizedBase
  }

  private func makeStaticServiceDescriptorProperty(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> VariableDescription {
    let serviceIdentifier = makeServiceIdentifier(service)

    return VariableDescription(
      accessModifier: self.accessModifier,
      isStatic: true,
      kind: .let,
      left: .identifierPattern("descriptor"),
      right: .memberAccess(
        MemberAccessDescription(
          left: .identifierPattern("ServiceDescriptor"),
          right: serviceIdentifier
        )
      )
    )
  }

  private func makeServiceDescriptorExtension(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let serviceIdentifier = makeServiceIdentifier(service)

    let serviceDescriptorInitialization = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member("Self")),
        arguments: [
          FunctionArgumentDescription(
            label: "package",
            expression: .literal(service.namespace.base)
          ),
          FunctionArgumentDescription(
            label: "service",
            expression: .literal(service.name.base)
          ),
        ]
      )
    )

    return .extension(
      ExtensionDescription(
        onType: "ServiceDescriptor",
        declarations: [
          .variable(
            VariableDescription(
              accessModifier: self.accessModifier,
              isStatic: true,
              kind: .let,
              left: .identifier(.pattern(serviceIdentifier)),
              right: serviceDescriptorInitialization
            )
          )
        ]
      )
    )
  }
}
