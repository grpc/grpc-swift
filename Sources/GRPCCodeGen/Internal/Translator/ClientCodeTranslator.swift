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

/// Creates a representation for the client code that will be generated based on the ``CodeGenerationRequest`` object
/// specifications, using types from ``StructuredSwiftRepresentation``.
///
/// For example, in the case of a service called "Bar", in the "foo" namespace which has
/// one method "baz", the ``ClientCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// public protocol Foo_BarClientProtocol: Sendable {
///   func baz<R: Sendable>(
///     request: ClientRequest.Single<foo.Bar.Method.baz.Input>,
///     serializer: some MessageSerializer<foo.Bar.Method.baz.Input>,
///     deserializer: some MessageDeserializer<foo.Bar.Method.baz.Output>,
///     _ body: @Sendable @escaping (ClientResponse.Single<foo.Bar.Method.Baz.Output>) async throws -> R
///   ) async throws -> ServerResponse.Stream<foo.Bar.Method.Baz.Output>
/// }
/// extension Foo.Bar.ClientProtocol {
///   public func get<R: Sendable>(
///     request: ClientRequest.Single<Foo.Bar.Method.Baz.Input>,
///     _ body: @Sendable @escaping (ClientResponse.Single<Foo.Bar.Method.Baz.Output>) async throws -> R
///   ) async rethrows -> R {
///     try await self.baz(
///       request: request,
///       serializer: ProtobufSerializer<Foo.Bar.Method.Baz.Input>(),
///       deserializer: ProtobufDeserializer<Foo.Bar.Method.Baz.Output>(),
///       body
///     )
/// }
/// public struct foo_BarClient: foo.Bar.ClientProtocol {
///   private let client: GRPCCore.GRPCClient
///   public init(client: GRPCCore.GRPCClient) {
///     self.client = client
///   }
///   public func methodA<R: Sendable>(
///     request: ClientRequest.Stream<namespaceA.ServiceA.Method.methodA.Input>,
///     serializer: some MessageSerializer<namespaceA.ServiceA.Method.methodA.Input>,
///     deserializer: some MessageDeserializer<namespaceA.ServiceA.Method.methodA.Output>,
///     _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Method.methodA.Output>) async throws -> R
///   ) async rethrows -> R {
///    try await self.client.clientStreaming(
///      request: request,
///      descriptor: NamespaceA.ServiceA.Method.MethodA.descriptor,
///      serializer: serializer,
///      deserializer: deserializer,
///      handler: body
///      )
///   }
/// }
///```
struct ClientCodeTranslator: SpecializedTranslator {
  var accessLevel: SourceGenerator.Configuration.AccessLevel

  init(accessLevel: SourceGenerator.Configuration.AccessLevel) {
    self.accessLevel = accessLevel
  }

  func translate(from codeGenerationRequest: CodeGenerationRequest) throws -> [CodeBlock] {
    var codeBlocks = [CodeBlock]()

    for service in codeGenerationRequest.services {
      codeBlocks.append(
        .declaration(
          .commentable(
            .preFormatted(service.documentation),
            self.makeClientProtocol(for: service, in: codeGenerationRequest)
          )
        )
      )
      codeBlocks.append(
        .declaration(self.makeExtensionProtocol(for: service, in: codeGenerationRequest))
      )
      codeBlocks.append(
        .declaration(
          .commentable(
            .preFormatted(service.documentation),
            self.makeClientStruct(for: service, in: codeGenerationRequest)
          )
        )
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
    let methods = service.methods.map {
      self.makeClientProtocolMethod(
        for: $0,
        in: service,
        from: codeGenerationRequest,
        generateSerializerDeserializer: false
      )
    }

    let clientProtocol = Declaration.protocol(
      ProtocolDescription(
        accessModifier: self.accessModifier,
        name: "\(service.namespacedGeneratedName)ClientProtocol",
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
    let methods = service.methods.map {
      self.makeClientProtocolMethod(
        for: $0,
        in: service,
        from: codeGenerationRequest,
        generateSerializerDeserializer: true,
        accessModifier: self.accessModifier
      )
    }
    let clientProtocolExtension = Declaration.extension(
      ExtensionDescription(
        onType: "\(service.namespacedTypealiasGeneratedName).ClientProtocol",
        declarations: methods
      )
    )
    return clientProtocolExtension
  }

  private func makeClientProtocolMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest,
    generateSerializerDeserializer: Bool,
    accessModifier: AccessModifier? = nil
  ) -> Declaration {
    let methodParameters = self.makeParameters(
      for: method,
      in: service,
      from: codeGenerationRequest,
      generateSerializerDeserializer: generateSerializerDeserializer
    )
    let functionSignature = FunctionSignatureDescription(
      accessModifier: accessModifier,
      kind: .function(
        name: method.name.generatedLowerCase,
        isStatic: false
      ),
      generics: [.member("R")],
      parameters: methodParameters,
      keywords: [.async, .throws],
      returnType: .identifierType(.member("R")),
      whereClause: WhereClause(requirements: [.conformance("R", "Sendable")])
    )

    if generateSerializerDeserializer {
      let body = self.makeSerializerDeserializerCall(
        for: method,
        in: service,
        from: codeGenerationRequest
      )
      return .function(signature: functionSignature, body: body)
    } else {
      return .commentable(
        .preFormatted(method.documentation),
        .function(signature: functionSignature)
      )
    }
  }

  private func makeSerializerDeserializerCall(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest
  ) -> [CodeBlock] {
    let functionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(
          left: .identifierPattern("self"),
          right: method.name.generatedLowerCase
        )
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
    generateSerializerDeserializer: Bool
  ) -> [ParameterDescription] {
    var parameters = [ParameterDescription]()

    parameters.append(self.clientRequestParameter(for: method, in: service))
    if !generateSerializerDeserializer {
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
    let requestType = method.isInputStreaming ? "Stream" : "Single"
    let clientRequestType = ExistingTypeDescription.member(["ClientRequest", requestType])
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
      type: ExistingTypeDescription.some(
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
      type: ExistingTypeDescription.some(
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

  private func makeClientStruct(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let clientProperty = Declaration.variable(
      accessModifier: .private,
      kind: .let,
      left: "client",
      type: .member(["GRPCCore", "GRPCClient"])
    )
    let initializer = self.makeClientVariable()
    let methods = service.methods.map {
      Declaration.commentable(
        .preFormatted($0.documentation),
        self.makeClientMethod(for: $0, in: service, from: codeGenerationRequest)
      )
    }

    return .struct(
      StructDescription(
        accessModifier: self.accessModifier,
        name: "\(service.namespacedGeneratedName)Client",
        conformances: ["\(service.namespacedTypealiasGeneratedName).ClientProtocol"],
        members: [clientProperty, initializer] + methods
      )
    )
  }

  private func makeClientVariable() -> Declaration {
    let initializerBody = Expression.assignment(
      left: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self"), right: "client")
      ),
      right: .identifierPattern("client")
    )
    return .function(
      signature: .init(
        accessModifier: self.accessModifier,
        kind: .initializer,
        parameters: [.init(label: "client", type: .member(["GRPCCore", "GRPCClient"]))]
      ),
      body: [CodeBlock(item: .expression(initializerBody))]
    )
  }

  private func clientMethod(
    isInputStreaming: Bool,
    isOutputStreaming: Bool
  ) -> String {
    switch (isInputStreaming, isOutputStreaming) {
    case (true, true):
      return "bidirectionalStreaming"
    case (true, false):
      return "clientStreaming"
    case (false, true):
      return "serverStreaming"
    case (false, false):
      return "unary"
    }
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
      generateSerializerDeserializer: false
    )
    let grpcMethodName = self.clientMethod(
      isInputStreaming: method.isInputStreaming,
      isOutputStreaming: method.isOutputStreaming
    )
    let functionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(left: .identifierPattern("self.client"), right: "\(grpcMethodName)")
      ),
      arguments: [
        .init(label: "request", expression: .identifierPattern("request")),
        .init(
          label: "descriptor",
          expression: .identifierPattern(
            "\(service.namespacedTypealiasGeneratedName).Method.\(method.name.generatedUpperCase).descriptor"
          )
        ),
        .init(label: "serializer", expression: .identifierPattern("serializer")),
        .init(label: "deserializer", expression: .identifierPattern("deserializer")),
        .init(label: "handler", expression: .identifierPattern("body")),
      ]
    )
    let body = UnaryKeywordDescription(
      kind: .try,
      expression: .unaryKeyword(kind: .await, expression: functionCall)
    )

    return .function(
      accessModifier: self.accessModifier,
      kind: .function(
        name: "\(method.name.generatedLowerCase)",
        isStatic: false
      ),
      generics: [.member("R")],
      parameters: parameters,
      keywords: [.async, .throws],
      returnType: .identifierType(.member("R")),
      whereClause: WhereClause(requirements: [.conformance("R", "Sendable")]),
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
    var components: String =
      "\(service.namespacedTypealiasGeneratedName).Method.\(method.name.generatedUpperCase)"

    switch type {
    case .input:
      components.append(".Input")
    case .output:
      components.append(".Output")
    }

    return components
  }
}
