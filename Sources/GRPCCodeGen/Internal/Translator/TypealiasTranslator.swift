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
    /// Sorting the keys and the services in each list of the dictionary is necessary
    /// so that the generated enums are deterministically ordered.
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
  private func makeNamespaceEnum(
    for namespace: String,
    containing services: [CodeGenerationRequest.ServiceDescriptor]
  ) throws -> [CodeBlock] {
    var namespaceEnum = EnumDescription(name: namespace)
    var serviceNames: Set<String> = []

    for service in services {
      /// Checking if service names are unique within the namespace.
      if serviceNames.contains(service.name) {
        let errorMessage: String
        if namespace.isEmpty {
          errorMessage = """
            Services with no namespace must have unique names. \
            \(service.name) is used as a name for multiple services without namespaces.
            """
        } else {
          errorMessage = """
            Services within the same namespace must have unique names. \
            \(service.name) is used as a name for multiple services in the \(service.namespace) namespace.
            """
        }
        throw CodeGenError(
          code: .sameNameServices,
          message: errorMessage
        )
      }
      let serviceEnum = try self.makeServiceEnum(from: service)
      namespaceEnum.members.append(serviceEnum)
      serviceNames.insert(service.name)
    }

    /// If the namespace is empty, the service enums are independent CodeBlocks.
    if namespace.isEmpty {
      return namespaceEnum.members.map {
        CodeBlock(item: .declaration($0))
      }
    }
    return [CodeBlock(item: .declaration(.enum(namespaceEnum)))]
  }

  private func makeServiceEnum(
    from service: CodeGenerationRequest.ServiceDescriptor
  ) throws -> Declaration {
    var serviceEnum = EnumDescription(name: service.name)
    var methodsEnum = EnumDescription(name: "Methods")
    var methodDescriptors: [Expression] = []
    var methodNames: Set<String> = []

    let methods = service.methods
    for method in methods {
      /// Checking if method names are unique within the service.
      if methodNames.contains(method.name) {
        throw CodeGenError(
          code: .sameNameMethods,
          message: """
            Methods of a service must have unique names. \
            \(method.name) is used as a name for multiple methods of the \(service.name) service.
            """
        )
      }
      let methodEnum = self.makeMethodEnum(from: method, in: service)
      methodsEnum.members.append(methodEnum)
      methodNames.insert(method.name)

      let typeMembers: [String]
      if service.namespace.isEmpty {
        typeMembers = [service.name, "Methods", method.name]
      } else {
        typeMembers = [service.namespace, service.name, "Methods", method.name]
      }

      let methodDescriptorPath = Expression.memberAccess(
        MemberAccessDescription(
          left: Expression.identifierType(.member(typeMembers)),
          right: "descriptor"
        )
      )
      methodDescriptors.append(methodDescriptorPath)
    }
    if !methodsEnum.members.isEmpty {
      serviceEnum.members.append(.enum(methodsEnum))
    }
    let methodDescriptorsDeclaration = self.makeMethodDescriptors(
      from: methodDescriptors
    )
    serviceEnum.members.append(methodDescriptorsDeclaration)

    let streamingServiceProtocolName: String
    let serviceProtocolName: String

    if service.namespace.isEmpty {
      streamingServiceProtocolName =
        "\(service.name)ServiceStreamingProtocol"
      serviceProtocolName = "\(service.name)ServiceProtocol"
    } else {
      streamingServiceProtocolName =
        "\(service.namespace)_\(service.name)ServiceStreamingProtocol"
      serviceProtocolName = "\(service.namespace)_\(service.name)ServiceProtocol"
    }

    let streamingServiceProtocolTypealias = Declaration.typealias(
      name: "StreamingServiceProtocol",
      existingType: .member([streamingServiceProtocolName])
    )
    let serviceProtocolTypealias = Declaration.typealias(
      name: "ServiceProtocol",
      existingType: .member([serviceProtocolName])
    )

    serviceEnum.members.append(streamingServiceProtocolTypealias)
    serviceEnum.members.append(serviceProtocolTypealias)
    return .enum(serviceEnum)
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
    let serviceArgumentName: String

    if service.namespace.isEmpty {
      serviceArgumentName = service.name
    } else {
      serviceArgumentName = "\(service.namespace).\(service.name)"
    }

    let descriptorDeclarationRight = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member(["MethodDescriptor"])),
        arguments: [
          FunctionArgumentDescription(
            label: "service",
            expression: .literal(serviceArgumentName)
          ),
          FunctionArgumentDescription(
            label: "method",
            expression: .literal(.string(method.name))
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
    from methodDescriptors: [Expression]
  ) -> Declaration {
    let methodDescriptorsDeclarationLeft = Expression.identifier(.pattern("methods"))
    let methodDescriptorsDeclarationRight = Expression.literal(
      LiteralDescription.array(methodDescriptors)
    )

    return .variable(
      isStatic: true,
      kind: .let,
      left: methodDescriptorsDeclarationLeft,
      type: .array(.member(["MethodDescriptor"])),
      right: methodDescriptorsDeclarationRight
    )
  }
}
