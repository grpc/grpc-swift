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

struct ClientCodeTranslator: SpecializedTranslator {
  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    var codeBlocks = [CodeBlock]()

    for service in codeGenerationRequest.services {
      codeBlocks.append(
        .declaration(self.makeClientProtocol(for: service, in: codeGenerationRequest))
      )
      codeBlocks.append(
        .declaration(self.makeExtensionProtocol(for: service, in: codeGenerationRequest))
      )
      codeBlocks.append(
        .declaration(self.makeClientStruct(for: service, in: codeGenerationRequest))
      )
    }
    return codeBlocks
  }
}

extension ClientCodeTranslator {
  private func makeClientProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    var methods = [Declaration]()
    for method in service.methods {
      methods.append(
        self.makeClientProtocolMethod(
          for: method,
          in: service,
          from: codeGenerationRequest,
          serializerDeserializer: true
        )
      )
    }

    let clientProtocol = Declaration.protocol(
      ProtocolDescription(
        name: "\(service.namespacedPrefix)ClientProtocol",
        conformances: ["Sendable"],
        members: methods
      )
    )
    return clientProtocol
  }

  private func makeExtensionProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let methods = service.methods.compactMap {
      self.makeClientProtocolMethod(
        for: $0,
        in: service,
        from: codeGenerationRequest,
        serializerDeserializer: false
      )
    }
    let clientProtocolExtension = Declaration.extension(
      ExtensionDescription(
        onType: "\(service.namespacedTypealiasPrefix).ClientProtocol",
        declarations: methods
      )
    )
    return clientProtocolExtension
  }

  private func makeClientProtocolMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest,
    serializerDeserializer: Bool
  ) -> Declaration {
    let methodParameters = self.makeParameters(
      for: method,
      in: service,
      from: codeGenerationRequest,
      serializerDeserializer: serializerDeserializer
    )
    let functionSignature = FunctionSignatureDescription(
      kind: .function(
        name: method.name,
        isStatic: false,
        genericType: "R",
        conformances: ["Sendable"]
      ),
      parameters: methodParameters,
      keywords: [.async, .rethrows],
      returnType: .identifierType(.member("R"))
    )

    if !serializerDeserializer {
      let body = self.makeSerializerDeserializerCall(
        for: method,
        in: service,
        from: codeGenerationRequest
      )
      return .function(signature: functionSignature, body: body)
    }
    return .function(signature: functionSignature)
  }

  private func makeSerializerDeserializerCall(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest
  ) -> [CodeBlock] {
    let functionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self"), right: method.name)
      ),
      arguments: [
        FunctionArgumentDescription(label: "request", expression: .identifierPattern("request")),
        FunctionArgumentDescription(
          label: "serializer",
          expression: .identifierPattern(
            codeGenerationRequest.lookupSerializer(
              self.methodInputOutputTypealias(for: method, service: service, type: .input)
            )
          )
        ),
        FunctionArgumentDescription(
          label: "deserializer",
          expression: .identifierPattern(
            codeGenerationRequest.lookupDeserializer(
              self.methodInputOutputTypealias(for: method, service: service, type: .output)
            )
          )
        ),
        FunctionArgumentDescription(expression: .identifierPattern("body")),
      ]
    )
    let awaitFunctionCall = Expression.unaryKeyword(kind: .await, expression: functionCall)
    let tryAwaitFunctionCall = Expression.unaryKeyword(kind: .try, expression: awaitFunctionCall)

    return [CodeBlock(item: .expression(tryAwaitFunctionCall))]
  }

  private func makeParameters(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest,
    serializerDeserializer: Bool
  ) -> [ParameterDescription] {
    var parameters = [ParameterDescription]()

    parameters.append(self.clientRequestParameter(for: method, in: service))
    if serializerDeserializer {
      parameters.append(self.serializerParameter(for: method, in: service))
      parameters.append(self.deserializerParameter(for: method, in: service))
    }
    parameters.append(self.bodyParameter(for: method, in: service))
    return parameters
  }
  private func clientRequestParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> ParameterDescription {
    let clientRequestType =
      method.isInputStreaming
      ? ExistingTypeDescription.member(["ClientRequest", "Stream"])
      : ExistingTypeDescription.member(["ClientRequest", "Single"])
    return ParameterDescription(
      label: "request",
      type: .generic(
        wrapper: clientRequestType,
        wrapped: .member(
          self.methodInputOutputTypealias(for: method, service: service, type: .input)
        )
      )
    )
  }

  private func serializerParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> ParameterDescription {
    return ParameterDescription(
      label: "serializer",
      type: .some(
        .generic(
          wrapper: .member("MessageSerializer"),
          wrapped: .member(
            self.methodInputOutputTypealias(for: method, service: service, type: .input)
          )
        )
      )
    )
  }

  private func deserializerParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> ParameterDescription {
    return ParameterDescription(
      label: "deserializer",
      type: .some(
        .generic(
          wrapper: .member("MessageDeserializer"),
          wrapped: .member(
            self.methodInputOutputTypealias(for: method, service: service, type: .output)
          )
        )
      )
    )
  }

  private func bodyParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> ParameterDescription {
    let clientStreaming = method.isOutputStreaming ? "Stream" : "Single"
    let closureParameterType = ExistingTypeDescription.generic(
      wrapper: .member(["ClientResponse", clientStreaming]),
      wrapped: .member(
        self.methodInputOutputTypealias(for: method, service: service, type: .output)
      )
    )

    let bodyClosure = ClosureSignatureDescription(
      parameters: [.init(type: closureParameterType)],
      keywords: [.async, .throws],
      returnType: .identifierType(.member("R")),
      sendable: true,
      escaping: true
    )
    return ParameterDescription(name: "body", type: .closure(bodyClosure))
  }

  private func clientResponseType(
    isOutputStreaming: Bool,
    serviceName: String
  ) -> ExistingTypeDescription {
    let clientRequestType =
      isOutputStreaming
      ? ExistingTypeDescription.member(["ClientResponse", "Stream"])
      : ExistingTypeDescription.member(["ClientRequest", "Single"])
    return .generic(wrapper: clientRequestType, wrapped: .member([serviceName, "Request"]))
  }

  private func makeClientStruct(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let initializer = self.makeClientVariable()
    let methods = service.methods.compactMap {
      self.makeClientMethod(for: $0, in: service, from: codeGenerationRequest)
    }

    return .struct(
      StructDescription(
        name: "\(service.namespacedPrefix)Client",
        conformances: ["\(service.namespacedTypealiasPrefix).ClientProtocol"],
        members: [initializer] + methods
      )
    )
  }

  private func makeClientVariable() -> Declaration {
    let clientParameter = Declaration.variable(
      kind: .let,
      left: "client",
      type: .member(["GRPCCore", "GRPCClient"])
    )
    let initializerBody = Expression.assignment(
      left: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self"), right: "client")
      ),
      right: .identifierPattern("client")
    )
    return .function(
      signature: .init(
        kind: .initializer,
        parameters: [.init(label: "client", type: .member(["GRPCCore", "GRPCClient"]))]
      ),
      body: [CodeBlock(item: .expression(initializerBody))]
    )
  }

  private func getGRPCMethodName(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  ) -> String {
    if method.isInputStreaming && method.isOutputStreaming {
      return "bidirectionalStreaming"
    }
    if method.isInputStreaming && !method.isOutputStreaming {
      return "clientStreaming"
    }
    if !method.isInputStreaming && method.isOutputStreaming {
      return "serverStreaming"
    }
    return "unary"
  }

  private func makeClientMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let parameters = self.makeParameters(
      for: method,
      in: service,
      from: codeGenerationRequest,
      serializerDeserializer: true
    )
    let grpcMethodName = self.getGRPCMethodName(for: method)
    let functionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self.client"), right: "\(grpcMethodName)")
      ),
      arguments: [
        .init(expression: .identifierPattern("request")),
        .init(
          expression: .identifierPattern(
            "\(service.namespacedTypealiasPrefix).Methods.\(method.name).descriptor"
          )
        ),
        .init(expression: .identifierPattern("serializer")),
        .init(expression: .identifierPattern("deserializer")),
        .init(expression: .identifierPattern("body")),
      ]
    )
    let body = UnaryKeywordDescription(
      kind: .try,
      expression: .unaryKeyword(kind: .await, expression: functionCall)
    )

    return .function(
      kind: .function(
        name: "\(method.name)",
        isStatic: false,
        genericType: "R",
        conformances: ["Sendable"]
      ),
      parameters: parameters,
      body: [.expression(.unaryKeyword(body))]
    )
  }

  fileprivate enum InputOutputType {
    case input
    case output
  }

  /// Generates the fully qualified name of the typealias for the input or output type of a method.
  private func methodInputOutputTypealias(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    service: CodeGenerationRequest.ServiceDescriptor,
    type: InputOutputType
  ) -> String {
    var components: String = "\(service.namespacedTypealiasPrefix).Methods.\(method.name)"

    switch type {
    case .input:
      components.append(".Input")
    case .output:
      components.append(".Output")
    }

    return components
  }
}
