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

/// Creates a representation for the server code that will be generated based on the ``CodeGenerationRequest`` object
/// specifications, using types from ``StructuredSwiftRepresentation``.
///
/// For example, in the case of a service called "Bar", in the "foo" namespace which has
/// one method "baz", the ``ServerCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// public protocol foo_BarServiceStreamingProtocol: GRPCCore.RegistrableRPCService {
///   func baz(
///     request: ServerRequest.Stream<foo.Method.baz.Input>
///   ) async throws -> ServerResponse.Stream<foo.Method.baz.Output>
/// }
/// // Generated conformance to `RegistrableRPCService`.
/// extension foo.Bar.StreamingServiceProtocol {
///   public func registerRPCs(with router: inout RPCRouter) {
///     router.registerHandler(
///       for: foo.Method.baz.descriptor,
///       deserializer: ProtobufDeserializer<foo.Methods.baz.Input>(),
///       serializer: ProtobufSerializer<foo.Methods.baz.Output>(),
///       handler: { request in try await self.baz(request: request) }
///     )
///   }
/// }
/// public protocol foo_BarServiceProtocol: foo.Bar.StreamingServiceProtocol {
///   func baz(
///     request: ServerRequest.Single<foo.Bar.Methods.baz.Input>
///   ) async throws -> ServerResponse.Single<foo.Bar.Methods.baz.Output>
/// }
/// // Generated partial conformance to `foo_BarStreamingServiceProtocol`.
/// extension foo.Bar.ServiceProtocol {
///   public func baz(
///     request: ServerRequest.Stream<foo.Bar.Methods.baz.Input>
///   ) async throws -> ServerResponse.Stream<foo.Bar.Methods.baz.Output> {
///     let response = try await self.baz(request: ServerRequest.Single(stream: request)
///     return ServerResponse.Stream(single: response)
///   }
/// }
///```
struct ServerCodeTranslator: SpecializedTranslator {
  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    var codeBlocks = [CodeBlock]()
    for service in codeGenerationRequest.services {
      // Create the streaming protocol that declares the service methods as bidirectional streaming.
      let streamingProtocol = CodeBlockItem.declaration(self.makeStreamingProtocol(for: service))
      codeBlocks.append(CodeBlock(item: streamingProtocol))

      // Create extension for implementing the 'registerRPCs' function which is a 'RegistrableRPCService' requirement.
      let conformanceToRPCServiceExtension = CodeBlockItem.declaration(
        self.makeConformanceToRPCServiceExtension(for: service, in: codeGenerationRequest)
      )
      codeBlocks.append(
        CodeBlock(
          comment: .doc("Conformance to `GRPCCore.RegistrableRPCService`."),
          item: conformanceToRPCServiceExtension
        )
      )

      // Create the service protocol that declares the service methods as they are described in the Source IDL (unary,
      // client/server streaming or bidirectional streaming).
      let serviceProtocol = CodeBlockItem.declaration(self.makeServiceProtocol(for: service))
      codeBlocks.append(CodeBlock(item: serviceProtocol))

      // Create extension for partial conformance to the streaming protocol.
      let extensionServiceProtocol = CodeBlockItem.declaration(
        self.makeExtensionServiceProtocol(for: service)
      )
      codeBlocks.append(
        CodeBlock(
          comment: .doc(
            "Partial conformance to `\(self.protocolName(service: service, streaming: true))`."
          ),
          item: extensionServiceProtocol
        )
      )
    }

    return codeBlocks
  }
}

extension ServerCodeTranslator {
  private func makeStreamingProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let methods = service.methods.compactMap {
      Declaration.commentable(
        .doc($0.documentation),
        .function(
          FunctionDescription(
            signature: self.makeStreamingMethodSignature(for: $0, in: service)
          )
        )
      )
    }

    let streamingProtocol = Declaration.protocol(
      .init(
        name: self.protocolName(service: service, streaming: true),
        conformances: ["GRPCCore.RegistrableRPCService"],
        members: methods
      )
    )

    return .commentable(.doc(service.documentation), streamingProtocol)
  }

  private func makeStreamingMethodSignature(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> FunctionSignatureDescription {
    return FunctionSignatureDescription(
      kind: .function(name: method.name),
      parameters: [
        .init(
          label: "request",
          type: .generic(
            wrapper: .member(["ServerRequest", "Stream"]),
            wrapped: .member(
              self.methodInputOutputTypealias(for: method, service: service, type: .input)
            )
          )
        )
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(
        .generic(
          wrapper: .member(["ServerResponse", "Stream"]),
          wrapped: .member(
            self.methodInputOutputTypealias(for: method, service: service, type: .output)
          )
        )
      )
    )
  }

  private func makeConformanceToRPCServiceExtension(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let streamingProtocol = self.protocolNameTypealias(service: service, streaming: true)
    let registerRPCMethod = self.makeRegisterRPCsMethod(for: service, in: codeGenerationRequest)
    return .extension(
      accessModifier: .public,
      onType: streamingProtocol,
      declarations: [registerRPCMethod]
    )
  }

  private func makeRegisterRPCsMethod(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let registerRPCsSignature = FunctionSignatureDescription(
      kind: .function(name: "registerRPCs"),
      parameters: [
        .init(
          label: "with",
          name: "router",
          type: .member(["GRPCCore", "RPCRouter"]),
          `inout`: true
        )
      ]
    )
    let registerRPCsBody = self.makeRegisterRPCsMethodBody(for: service, in: codeGenerationRequest)
    return .function(signature: registerRPCsSignature, body: registerRPCsBody)
  }

  private func makeRegisterRPCsMethodBody(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> [CodeBlock] {
    let registerHandlerCalls = service.methods.compactMap {
      CodeBlock.expression(
        Expression.functionCall(
          calledExpression: .memberAccess(
            MemberAccessDescription(left: .identifierPattern("router"), right: "registerHandler")
          ),
          arguments: self.makeArgumentsForRegisterHandler(
            for: $0,
            in: service,
            from: codeGenerationRequest
          )
        )
      )
    }

    return registerHandlerCalls
  }

  private func makeArgumentsForRegisterHandler(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest
  ) -> [FunctionArgumentDescription] {
    var arguments = [FunctionArgumentDescription]()
    arguments.append(
      .init(
        label: "for",
        expression: .identifierPattern(
          self.methodDescriptorPath(for: method, service: service)
        )
      )
    )

    arguments.append(
      .init(
        label: "deserializer",
        expression: .identifierPattern(
          codeGenerationRequest.lookupDeserializer(
            self.methodInputOutputTypealias(for: method, service: service, type: .input)
          )
        )
      )
    )

    arguments.append(
      .init(
        label: "serializer",
        expression:
          .identifierPattern(
            codeGenerationRequest.lookupSerializer(
              self.methodInputOutputTypealias(for: method, service: service, type: .output)
            )
          )
      )
    )

    let getFunctionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self"), right: method.name)
      ),
      arguments: [
        FunctionArgumentDescription(label: "request", expression: .identifierPattern("request"))
      ]
    )

    let handlerClosureBody = Expression.unaryKeyword(
      kind: .try,
      expression: .unaryKeyword(kind: .await, expression: getFunctionCall)
    )

    arguments.append(
      .init(
        label: "handler",
        expression: .closureInvocation(
          .init(argumentNames: ["request"], body: [.expression(handlerClosureBody)])
        )
      )
    )

    return arguments
  }

  private func makeServiceProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let methods = service.methods.compactMap {
      self.makeServiceProtocolMethod(for: $0, in: service)
    }
    let protocolName = self.protocolName(service: service, streaming: false)
    let streamingProtocol = self.protocolNameTypealias(service: service, streaming: true)

    return .commentable(
      .doc(service.documentation),
      .protocol(
        ProtocolDescription(name: protocolName, conformances: [streamingProtocol], members: methods)
      )
    )
  }

  private func makeServiceProtocolMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let inputStreaming = method.isInputStreaming ? "Stream" : "Single"
    let outputStreaming = method.isOutputStreaming ? "Stream" : "Single"

    let inputTypealiasComponents = self.methodInputOutputTypealias(
      for: method,
      service: service,
      type: .input
    )
    let outputTypealiasComponents = self.methodInputOutputTypealias(
      for: method,
      service: service,
      type: .output
    )

    let functionSignature = FunctionSignatureDescription(
      kind: .function(name: method.name),
      parameters: [
        .init(
          label: "request",
          type:
            .generic(
              wrapper: .member(["ServerRequest", inputStreaming]),
              wrapped: .member(inputTypealiasComponents)
            )
        )
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(
        .generic(
          wrapper: .member(["ServerResponse", outputStreaming]),
          wrapped: .member(outputTypealiasComponents)
        )
      )
    )

    return .commentable(
      .doc(method.documentation),
      .function(FunctionDescription(signature: functionSignature))
    )
  }

  private func makeExtensionServiceProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    let methods = service.methods.compactMap {
      self.makeServiceProtocolExtensionMethod(for: $0, in: service)
    }

    let protocolName = self.protocolNameTypealias(service: service, streaming: false)
    return .extension(accessModifier: .public, onType: protocolName, declarations: methods)
  }

  private func makeServiceProtocolExtensionMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration? {
    // The method has the same definition in StreamingServiceProtocol and ServiceProtocol.
    if method.isInputStreaming && method.isOutputStreaming {
      return nil
    }

    let response = CodeBlock(item: .declaration(self.makeResponse(for: method)))
    let returnStatement = CodeBlock(item: .expression(self.makeReturnStatement(for: method)))

    return .function(
      signature: self.makeStreamingMethodSignature(for: method, in: service),
      body: [response, returnStatement]
    )
  }

  private func makeResponse(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  ) -> Declaration {
    let serverRequest: Expression
    if !method.isInputStreaming {
      // Transform the streaming request into a unary request.
      serverRequest = Expression.functionCall(
        calledExpression: .memberAccess(
          MemberAccessDescription(
            left: .identifierPattern("ServerRequest"),
            right: "Single"
          )
        ),
        arguments: [
          FunctionArgumentDescription(label: "stream", expression: .identifierPattern("request"))
        ]
      )
    } else {
      serverRequest = Expression.identifierPattern("request")
    }
    // Call to the corresponding ServiceProtocol method.
    let serviceProtocolMethod = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self"), right: method.name)
      ),
      arguments: [FunctionArgumentDescription(label: "request", expression: serverRequest)]
    )

    let responseValue = Expression.unaryKeyword(
      kind: .try,
      expression: .unaryKeyword(kind: .await, expression: serviceProtocolMethod)
    )

    return .variable(kind: .let, left: "response", right: responseValue)
  }

  private func makeReturnStatement(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  ) -> Expression {
    let returnValue: Expression
    // Transforming the unary response into a streaming one.
    if !method.isOutputStreaming {
      returnValue = .functionCall(
        calledExpression: .memberAccess(
          MemberAccessDescription(
            left: .identifierType(.member(["ServerResponse"])),
            right: "Stream"
          )
        ),
        arguments: [
          (FunctionArgumentDescription(label: "single", expression: .identifierPattern("response")))
        ]
      )
    } else {
      returnValue = .identifierPattern("response")
    }

    return .unaryKeyword(kind: .return, expression: returnValue)
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

  /// Generates the fully qualified name of a method descriptor.
  private func methodDescriptorPath(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    service: CodeGenerationRequest.ServiceDescriptor
  ) -> String {
    return "\(service.namespacedTypealiasPrefix).Methods.\(method.name).descriptor"
  }

  /// Generates the fully qualified name of the type alias for a service protocol.
  internal func protocolNameTypealias(
    service: CodeGenerationRequest.ServiceDescriptor,
    streaming: Bool
  ) -> String {
    if streaming {
      return "\(service.namespacedTypealiasPrefix).StreamingServiceProtocol"
    }
    return "\(service.namespacedTypealiasPrefix).ServiceProtocol"
  }

  /// Generates the name of a service protocol.
  internal func protocolName(
    service: CodeGenerationRequest.ServiceDescriptor,
    streaming: Bool
  ) -> String {
    if streaming {
      return "\(service.namespacedPrefix)StreamingServiceProtocol"
    }
    return "\(service.namespacedPrefix)ServiceProtocol"
  }
}
