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
/// public enum Echo {
///   public enum Echo {
///     public enum Method {
///       public enum Get {
///         public typealias Input = Echo_EchoRequest
///         public typealias Output = Echo_EchoResponse
///         public static let descriptor = MethodDescriptor(service: "echo.Echo", method: "Get")
///       }
///
///       public enum Collect {
///         public typealias Input = Echo_EchoRequest
///         public typealias Output = Echo_EchoResponse
///         public static let descriptor = MethodDescriptor(service: "echo.Echo", method: "Collect")
///       }
///       // ...
///
///       public static let descriptors: [MethodDescriptor] = [
///         Echo.Echo.Method.Get.descriptor,
///         Echo.Echo.Method.Collect.descriptor,
///         // ...
///       ]
///     }
///
///     public typealias StreamingServiceProtocol = echo_EchoServiceStreamingProtocol
///     public typealias ServiceProtocol = echo_EchoServiceProtocol
///
///   }
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
    let servicesByNamespace = Dictionary(
      grouping: services,
      by: { $0.namespace.generatedUpperCase }
    )

    // Sorting the keys and the services in each list of the dictionary is necessary
    // so that the generated enums are deterministically ordered.
    for (generatedNamespace, services) in servicesByNamespace.sorted(by: { $0.key < $1.key }) {
      let namespaceCodeBlocks = try self.makeNamespaceEnum(
        for: generatedNamespace,
        containing: services.sorted(by: { $0.name.generatedUpperCase < $1.name.generatedUpperCase })
      )
      codeBlocks.append(contentsOf: namespaceCodeBlocks)
    }

    return codeBlocks
  }
}

extension TypealiasTranslator {
  private func makeNamespaceEnum(
    for namespace: String,
    containing services: [CodeGenerationRequest.ServiceDescriptor]
  ) throws -> [CodeBlock] {
    var serviceDeclarations = [Declaration]()

    // Create the service specific enums.
    for service in services {
      let serviceEnum = try self.makeServiceEnum(from: service)
      serviceDeclarations.append(serviceEnum)
    }

    // If there is no namespace, the service enums are independent CodeBlocks.
    // If there is a namespace, the associated enum will contain the service enums and will
    // be represented as a single CodeBlock element.
    if namespace.isEmpty {
      return serviceDeclarations.map {
        CodeBlock(item: .declaration($0))
      }
    } else {
      var namespaceEnum = EnumDescription(accessModifier: self.accessModifier, name: namespace)
      namespaceEnum.members = serviceDeclarations
      return [CodeBlock(item: .declaration(.enum(namespaceEnum)))]
    }
  }

  private func makeServiceEnum(
    from service: CodeGenerationRequest.ServiceDescriptor
  ) throws -> Declaration {
    var serviceEnum = EnumDescription(
      accessModifier: self.accessModifier,
      name: service.name.generatedUpperCase
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
    let descriptorDeclarationLeft = Expression.identifier(.pattern("descriptor"))
    let descriptorDeclarationRight = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member("MethodDescriptor")),
        arguments: [
          FunctionArgumentDescription(
            label: "service",
            expression: .literal(service.fullyQualifiedName)
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
            .member([service.namespacedTypealiasGeneratedName, "Method", methodName])
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

    return [streamingServiceProtocolTypealias, serviceProtocolTypealias]
  }

  private func makeClientProtocolTypealias(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    return .typealias(
      accessModifier: self.accessModifier,
      name: "ClientProtocol",
      existingType: .member("\(service.namespacedGeneratedName)ClientProtocol")
    )
  }

  private func makeClientStructTypealias(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    return .typealias(
      accessModifier: self.accessModifier,
      name: "Client",
      existingType: .member("\(service.namespacedGeneratedName)Client")
    )
  }
}
