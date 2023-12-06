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
///     public enum Get {
///       public typealias Input = Echo_EchoRequest
///       public typealias Output = Echo_EchoResponse
///       public static let descriptor = MethodDescriptor(service: "echo.Echo", method: "Get")
///     }
///
///     public enum Collect {
///       public typealias Input = Echo_EchoRequest
///       public typealias Output = Echo_EchoResponse
///       public static let descriptor = MethodDescriptor(service: "echo.Echo", method: "Collect")
///     }
///     // ...
///
///   public static let methods: [MethodDescriptor] = [
///     echo.Echo.Get.descriptor,
///     echo.Echo.Collect.descriptor,
///     // ...
///   ]
///
///   public typealias StreamingServiceProtocol = echo_EchoServiceStreamingProtocol
///   public typealias ServiceProtocol = echo_EchoServiceProtocol
///
///   }
/// }
/// ```
///
/// A ``CodeGenerationRequest`` can contain multiple namespaces, so the TypealiasTranslator will create a ``CodeBlock``
/// for each namespace.
struct TypealiasTranslator: SpecializedTranslator {
  func translate(from codeGenerationRequest: CodeGenerationRequest) -> [CodeBlock] {
    var codeBlocks: [CodeBlock] = []
    let services = codeGenerationRequest.services
    let arrayOfServicesByNamespace = Dictionary(grouping: services, by: { $0.namespace }).sorted(
      by: { $0.key < $1.key })
    for (namespace, listOfServices) in arrayOfServicesByNamespace {
      let namespaceEnumDeclaration = self.makeNamespaceTypealiasesEnum(
        for: namespace,
        containing: listOfServices.sorted(by: { $0.name < $1.name })
      )
      let codeBlockItem = CodeBlockItem.declaration(namespaceEnumDeclaration)
      codeBlocks.append(CodeBlock(item: codeBlockItem))
    }

    return codeBlocks
  }
}

extension TypealiasTranslator {
  func makeNamespaceTypealiasesEnum(
    for namespace: String,
    containing services: [CodeGenerationRequest.ServiceDescriptor]
  ) -> Declaration {
    var namespaceEnumDescription = EnumDescription(name: namespace)

    for service in services {
      let serviceEnumDeclaration = self.makeServiceTypealiasesEnum(from: service)
      namespaceEnumDescription.members.append(serviceEnumDeclaration)
    }

    return .enum(namespaceEnumDescription)
  }

  func makeServiceTypealiasesEnum(
    from service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var serviceEnumDescription = EnumDescription(name: service.name)
    var methodDescriptorFullyQualifiedPathArray: [Expression] = []
    let methods = service.methods.sorted(by: { $0.name < $1.name })
    for method in methods {
      let methodEnumDeclaration = self.makeMethodTypealiasesEnum(from: method, in: service)
      serviceEnumDescription.members.append(methodEnumDeclaration)

      let methodDescriptorFullyQualifiedPath = Expression.memberAccess(
        MemberAccessDescription(
          left: Expression.identifierType(.member([service.namespace, service.name, method.name])),
          right: "descriptor"
        )
      )
      methodDescriptorFullyQualifiedPathArray.append(methodDescriptorFullyQualifiedPath)
    }

    let methodDescriptorArrayDeclaration = self.makeMethodDescriptorArray(
      from: methodDescriptorFullyQualifiedPathArray
    )
    serviceEnumDescription.members.append(methodDescriptorArrayDeclaration)

    let streamingServiceProtocolName =
      "\(service.namespace)_\(service.name)ServiceStreamingProtocol"
    let streamingServiceProtocolTypealiasDeclaration = Declaration.typealias(
      name: "StreamingServiceProtocol",
      existingType: .member([streamingServiceProtocolName])
    )

    let serviceProtocolName = "\(service.namespace)_\(service.name)ServiceProtocol"
    let serviceProtocolTypealiasDeclaration = Declaration.typealias(
      name: "ServiceProtocol",
      existingType: .member([serviceProtocolName])
    )

    serviceEnumDescription.members.append(contentsOf: [
      streamingServiceProtocolTypealiasDeclaration, serviceProtocolTypealiasDeclaration,
    ])

    return .enum(serviceEnumDescription)
  }

  func makeMethodTypealiasesEnum(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var methodEnumDescription = EnumDescription(name: method.name)

    let inputTypealiasDeclaration = Declaration.typealias(
      name: "Input",
      existingType: .member([method.inputType])
    )
    let outputTypealiasDeclaration = Declaration.typealias(
      name: "Output",
      existingType: .member([method.outputType])
    )
    let descriptorVariableDeclaration = self.makeMethodDescriptor(
      from: method,
      in: service
    )
    methodEnumDescription.members.append(contentsOf: [
      inputTypealiasDeclaration, outputTypealiasDeclaration, descriptorVariableDeclaration,
    ])

    return .enum(methodEnumDescription)
  }

  func makeMethodDescriptor(
    from method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let descriptorDeclarationLeft = Expression.identifier(.pattern("descriptor"))
    let descriptorDeclarationRight = Expression.functionCall(
      FunctionCallDescription(
        calledExpression: .identifierType(.member(["MethodDescriptor"])),
        arguments: [
          FunctionArgumentDescription(
            label: "service",
            expression: .identifierType(.member([service.namespace, service.name]))
          ),
          FunctionArgumentDescription(
            label: "method",
            expression: .identifierType(.member([method.name]))
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

  func makeMethodDescriptorArray(
    from methodDescriptorArray: [Expression]
  ) -> Declaration {
    let methodDescriptorArrayDeclarationLeft = Expression.identifier(.pattern("methods"))
    let methodDescriptorArrayDeclarationRight = Expression.literal(
      LiteralDescription.array(methodDescriptorArray)
    )

    return .variable(
      isStatic: true,
      kind: .let,
      left: methodDescriptorArrayDeclarationLeft,
      type: .array(.member(["MethodDescriptor"])),
      right: methodDescriptorArrayDeclarationRight
    )
  }
}
