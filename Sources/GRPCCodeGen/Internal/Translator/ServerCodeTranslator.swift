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

/// Creates a representation for the server code that will be generated based on the``CodeGenerationRequest`` object
/// specifications, using types from``StructuredSwiftRepresentation``.
///
/// For example, in the case of the ``Echo`` service, the ``ServerCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// public protocol echo.Echo.ServiceStreamingProtocol: RPCService, Sendable {
///  func get(
///   request: ServerRequest.Stream<echo.Method.Get.Input>
///  ) async throws -> ServerResponse.Stream<echo.Method.Get.Output>
///
///  func collect(
///   request: ServerRequest.Stream<echo.Method.Collect.Input>
///  ) async throws -> ServerResponse.Stream<echo.Method.Collect.Output>
///
///  func expand(
///    request: ServerRequest.Stream<echo.Method.Expand.Input>
///  ) async throws -> ServerResponse.Stream<echo.Method.Expand.Output>
///
///  func update(
///    request: ServerRequest.Stream<echo.Method.Update.Input>
///  ) async throws -> ServerResponse.Stream<echo.Method.Update.Output>
/// }
///
///
/// // Generated conformance to `RegistrableRPCService`.
/// extension echo.Echo.StreamingServiceProtocol {
///  public func registerRPCs(with router: inout RPCRouter) {
///    router.registerHandler(
///      for: echo.Method.Get.descriptor,
///      deserializer: ProtobufDeserializer<echo.Method.Get.Input>(),
///      serializer: ProtobufSerializer<echo.Method.Get.Output>(),
///      handler: { request in try await self.get(request) }
///    )
///    router.registerHandler(...)
/// }
///
/// public protocol echo.Echo.ServiceProtocol: echo.Echo.StreamingServiceProtocol {
///   func get(
///     request: ServerRequest.Single<EchoRequest>
///   ) async throws -> ServerResponse.Single<EchoResponse>
///
///   func collect(
///     request: ServerRequest.Stream<EchoResponse>
///   ) async throws -> ServerResponse.Single<EchoResponse>
///
///   func expand(
///     request: ServerRequest.Single<EchoRequest>
///   ) async throws -> ServerResponse.Stream<EchoResponse>
///
///   func update(
///     request: ServerRequest.Stream<EchoResponse>
///   ) async throws -> ServerResponse.Stream<EchoResponse>
/// }
///
///
/// // Generated partial conformance to `echo.Echo.StreamingServiceProtocol`.
/// extension echo.Echo.ServiceProtocol {
///  public func get(
///    request: ServerRequest.Stream<EchoRequest>
///  ) async throws -> ServerResponse.Stream<EchoResponse> {
///    let response = try await self.get(request: ServerRequest.Single(stream: request)
///    return ServerResponse.Stream(single: response)
///  }
///
///  public func collect(
///    request: ServerRequest.Stream<EchoResponse>
///  ) async throws -> ServerResponse.Stream<EchoResponse> {
///    let response = try await self.collect(request: request))
///    return ServerResponse.Stream(single: response)
///  }
///
///  public func expand(
///  request: ServerRequest.Stream<EchoRequest>
///  ) async throws -> ServerResponse.Stream<EchoResponse> {
///    let response = try await self.expand(request: ServerRequest.Single(stream: request))
///    return response
///  }
///}
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
          comment: .inline("Generated conformance to `RegistrableRPCService`."),
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
          comment: .inline(
            "Generated partial conformance to `\(self.serviceProtocolName(for: service, streaming: true))`."
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
    var methods = [Declaration]()
    for method in service.methods {
      methods.append(
        .function(
          signature: FunctionSignatureDescription(
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
        )
      )
    }

    let streamingProtocol = Declaration.protocol(
      .init(
        name: self.serviceProtocolName(for: service, streaming: true),
        conformances: ["RegistrableRPCService", "Sendable"],
        members: methods
      )
    )

    return streamingProtocol
  }

  private func makeConformanceToRPCServiceExtension(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let streamingProtocol = self.serviceProtocolName(for: service, streaming: true)
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
      parameters: [.init(label: "with", name: "router", type: .inout(.member(["RPCRouter"])))]
    )
    let registerRPCsBody = self.makeRegisterRPCsMethodBody(for: service, in: codeGenerationRequest)
    return .function(signature: registerRPCsSignature, body: registerRPCsBody)
  }

  private func makeRegisterRPCsMethodBody(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> [CodeBlock]? {
    var registerHandlerCalls = [CodeBlock]()
    for method in service.methods {
      let arguments = self.makeArgumentsForRegisterHandler(
        for: method,
        in: service,
        from: codeGenerationRequest
      )
      let registerHandlerCall = Expression.functionCall(
        calledExpression: .memberAccess(
          MemberAccessDescription(left: .identifierPattern("router"), right: "registerHandler")
        ),
        arguments: arguments
      )

      registerHandlerCalls.append(.expression(registerHandlerCall))
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
      arguments: [FunctionArgumentDescription(expression: .identifierPattern("request"))]
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
    var methods = [Declaration]()
    for method in service.methods {
      let methodDeclaration = self.makeServiceProtocolMethod(for: method, in: service)
      methods.append(methodDeclaration)
    }
    let protocolName = self.serviceProtocolName(for: service, streaming: false)
    let streamingProtocol = self.serviceProtocolName(for: service, streaming: true)

    return .protocol(
      ProtocolDescription(name: protocolName, conformances: [streamingProtocol], members: methods)
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

    return .function(FunctionDescription(signature: functionSignature))
  }

  private func makeExtensionServiceProtocol(
    for service: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration {
    var methods = [Declaration]()
    for method in service.methods {
      if let methodDeclaration = self.makeServiceProtocolExtensionMethod(for: method, in: service) {
        methods.append(methodDeclaration)
      }
    }
    let protocolName = self.serviceProtocolName(for: service, streaming: false)
    return .extension(accessModifier: .public, onType: protocolName, declarations: methods)
  }

  private func makeServiceProtocolExtensionMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in: CodeGenerationRequest.ServiceDescriptor
  ) -> Declaration? {
    // The method has the same definition in StreamingServiceProtocol and ServiceProtocol.
    if method.isInputStreaming && method.isOutputStreaming {
      return nil
    }

    let response = CodeBlock(item: .declaration(self.makeResponse(for: method)))
    let returnStatement = CodeBlock(item: .expression(self.makeReturnStatement(for: method)))

    return .function(
      signature: FunctionSignatureDescription(kind: .function(name: method.name)),
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

  /// Generates the fully qualified name of the type alias for a service descriptor.
  private func serviceProtocolName(
    for service: CodeGenerationRequest.ServiceDescriptor,
    streaming: Bool
  ) -> String {
    let namespacedPrefix: String
    if service.namespace.isEmpty {
      namespacedPrefix = service.name
    } else {
      namespacedPrefix = "\(service.namespace).\(service.name)"
    }
    if streaming {
      return "\(namespacedPrefix).StreamingServiceProtocol"
    }
    return "\(namespacedPrefix).ServiceProtocol"
  }

  private func fullyQualifiedMethodDescriptor() {}

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
    var components: String = ""
    if service.namespace.isEmpty {
      components = "\(service.name).Methods.\(method.name)"
    } else {
      components = "\(service.namespace).\(service.name).Methods.\(method.name)"
    }

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
    var components: String = ""
    if service.namespace.isEmpty {
      components = "\(service.name).Methods.\(method.name)"
    } else {
      components = "\(service.namespace).\(service.name).Methods.\(method.name)"
    }

    return components.appending(".descriptor")
  }
}
