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
/// public enum echo {
///   public enum Echo {
///     public enum Methods {
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
///     }
///     public static let methods: [MethodDescriptor] = [
///       echo.Echo.Get.descriptor,
///       echo.Echo.Collect.descriptor,
///       // ...
///     ]
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
  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    var codeBlocks: [CodeBlock] = []
    let services = codeGenerationRequest.services
    let servicesByNamespace = Dictionary(grouping: services, by: { $0.namespace })

    // Verify service names are unique within each namespace and that services with no namespace
    // don't have the same names as any of the namespaces.
    try self.checkServiceNamesAreUnique(for: servicesByNamespace)

    // Sorting the keys and the services in each list of the dictionary is necessary
    // so that the generated enums are deterministically ordered.
    for (namespace, services) in servicesByNamespace.sorted(by: { $0.key < $1.key }) {
      let namespaceCodeBlocks = try self.makeNamespaceEnum(
        for: namespace,
        containing: services.sorted(by: { $0.name < $1.name })
      )
      codeBlocks.append(contentsOf: namespaceCodeBlocks)
    }

    return codeBlocks
  }
}

extension TypealiasTranslator {
  private func checkServiceNamesAreUnique(
    for servicesByNamespace: [String: [CodeGenerationRequest.ServiceDescriptor]]
  ) throws {
    // Check that if there are services in an empty namespace, none have names which match other namespaces
    let noNamespaceServices = servicesByNamespace["", default: []]
    let namespaces = servicesByNamespace.keys
    for service in noNamespaceServices {
      if namespaces.contains(service.name) {
        throw CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services with no namespace must not have the same names as the namespaces. \
            \(service.name) is used as a name for a service with no namespace and a namespace.
            """
        )
      }
    }

    // Check that service names are unique within each namespace.
    for (namespace, services) in servicesByNamespace {
      var serviceNames: Set<String> = []
      for service in services {
        if serviceNames.contains(service.name) {
          let errorMessage: String
          if namespace.isEmpty {
            errorMessage = """
              Services in an empty namespace must have unique names. \
              \(service.name) is used as a name for multiple services without namespaces.
              """
          } else {
            errorMessage = """
              Services within the same namespace must have unique names. \
              \(service.name) is used as a name for multiple services in the \(service.namespace) namespace.
              """
          }
          throw CodeGenError(
            code: .nonUniqueServiceName,
            message: errorMessage
          )
        }
        serviceNames.insert(service.name)
      }
    }
  }

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
      var namespaceEnum = EnumDescription(name: namespace)
      namespaceEnum.members = serviceDeclarations
      return [CodeBlock(item: .declaration(.enum(namespaceEnum)))]
    }
  }

  private func makeServiceEnum(
    from service: CodeGenerationRequest.ServiceDescriptor
  ) throws -> Declaration {
    var serviceEnum = EnumDescription(name: service.name)
    var methodsEnum = EnumDescription(name: "Methods")
    let methods = service.methods

    // Verify method names are unique for the service.
    try self.checkMethodNamesAreUnique(in: service)

    // Create the method specific enums.
    for method in methods {
      let methodEnum = self.makeMethodEnum(from: method, in: service)
      methodsEnum.members.append(methodEnum)
    }
    serviceEnum.members.append(.enum(methodsEnum))

    // Create the method descriptor array.
    let methodDescriptorsDeclaration = self.makeMethodDescriptors(for: service)
    serviceEnum.members.append(methodDescriptorsDeclaration)

    // Create the streaming and non-streaming service protocol type aliases.
    let serviceProtocols = self.makeServiceProtocolsTypealiases(for: service)
    serviceEnum.members.append(contentsOf: serviceProtocols)

    return .enum(serviceEnum)
  }

  private func checkMethodNamesAreUnique(
    in service: CodeGenerationRequest.ServiceDescriptor
  ) throws {
    let methodNames = service.methods.map { $0.name }
    var seenNames = Set<String>()

    for methodName in methodNames {
      if seenNames.contains(methodName) {
        throw CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique names. \
            \(methodName) is used as a name for multiple methods of the \(service.name) service.
            """
        )
      }
      seenNames.insert(methodName)
    }
  }

  private func makeMethodEnum(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var methodEnum = EnumDescription(name: method.name)

    let inputTypealias = Declaration.typealias(
      name: "Input",
      existingType: .member([method.inputType])
    )
    let outputTypealias = Declaration.typealias(
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

    return .enum(methodEnum)
  }

  private func makeMethodDescriptor(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let descriptorDeclarationLeft = Expression.identifier(.pattern("descriptor"))

    let fullyQualifiedServiceName: String
    if service.namespace.isEmpty {
      fullyQualifiedServiceName = service.name
    } else {
      fullyQualifiedServiceName = "\(service.namespace).\(service.name)"
    }

    let descriptorDeclarationRight = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member(["MethodDescriptor"])),
        arguments: [
          FunctionArgumentDescription(
            label: "service",
            expression: .literal(fullyQualifiedServiceName)
          ),
          FunctionArgumentDescription(
            label: "method",
            expression: .literal(method.name)
          ),
        ]
      )
    )
    return .variable(
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
    let methodNames = service.methods.map { $0.name }

    for methodName in methodNames {
      let methodDescriptorPath = Expression.memberAccess(
        MemberAccessDescription(
          left: .identifierType(.member(["Methods", methodName])),
          right: "descriptor"
        )
      )
      methodDescriptors.append(methodDescriptorPath)
    }

    return .variable(
      isStatic: true,
      kind: .let,
      left: .identifier(.pattern("methods")),
      type: .array(.member(["MethodDescriptor"])),
      right: .literal(.array(methodDescriptors))
    )
  }

  private func makeServiceProtocolsTypealiases(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> [Declaration] {
    let namespacedPrefix: String

    if service.namespace.isEmpty {
      namespacedPrefix = service.name
    } else {
      namespacedPrefix = "\(service.namespace)_\(service.name)"
    }

    let streamingServiceProtocolName = "\(namespacedPrefix)ServiceStreamingProtocol"
    let streamingServiceProtocolTypealias = Declaration.typealias(
      name: "StreamingServiceProtocol",
      existingType: .member([streamingServiceProtocolName])
    )

    let serviceProtocolName = "\(namespacedPrefix)ServiceProtocol"
    let serviceProtocolTypealias = Declaration.typealias(
      name: "ServiceProtocol",
      existingType: .member([serviceProtocolName])
    )

    return [streamingServiceProtocolTypealias, serviceProtocolTypealias]
  }
}
