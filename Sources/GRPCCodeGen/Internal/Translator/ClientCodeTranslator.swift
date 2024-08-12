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
/// one method "baz" with input type "Input" and output type "Output", the ``ClientCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarClientProtocol: Sendable {
///   func baz<R>(
///     request: GRPCCore.ClientRequest.Single<Foo_Bar_Input>,
///     serializer: some GRPCCore.MessageSerializer<Foo_Bar_Input>,
///     deserializer: some GRPCCore.MessageDeserializer<Foo_Bar_Output>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Foo_Bar_Output>) async throws -> R
///   ) async throws -> R where R: Sendable
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.ClientProtocol {
///   public func baz<R>(
///     request: GRPCCore.ClientRequest.Single<Foo_Bar_Input>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Foo_Bar_Output>) async throws -> R = {
///       try $0.message
///     }
///   ) async throws -> R where R: Sendable {
///     try await self.baz(
///       request: request,
///       serializer: GRPCProtobuf.ProtobufSerializer<Foo_Bar_Input>(),
///       deserializer: GRPCProtobuf.ProtobufDeserializer<Foo_Bar_Output>(),
///       options: options,
///       body
///     )
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public struct Foo_BarClient: Foo_Bar.ClientProtocol {
///   private let client: GRPCCore.GRPCClient
///   public init(wrapping client: GRPCCore.GRPCClient) {
///     self.client = client
///   }
///   public func methodA<R>(
///     request: GRPCCore.ClientRequest.Stream<Foo_Bar_Input>,
///     serializer: some GRPCCore.MessageSerializer<Foo_Bar_Input>,
///     deserializer: some GRPCCore.MessageDeserializer<Foo_Bar_Output>,
///     options: GRPCCore.CallOptions = .defaults,
///     _ body: @Sendable @escaping (GRPCCore.ClientResponse.Single<Foo_Bar_Output>) async throws -> R = {
///       try $0.message
///     }
///   ) async throws -> R where R: Sendable {
///     try await self.client.unary(
///       request: request,
///       descriptor: NamespaceA.ServiceA.Method.MethodA.descriptor,
///       serializer: serializer,
///       deserializer: deserializer,
///       options: options,
///       handler: body
///     )
///   }
/// }
///```
struct ClientCodeTranslator: SpecializedTranslator {
  var accessLevel: SourceGenerator.Configuration.AccessLevel

  init(accessLevel: SourceGenerator.Configuration.AccessLevel) {
    self.accessLevel = accessLevel
  }

  func translate(from request: CodeGenerationRequest) throws -> [CodeBlock] {
    var blocks = [CodeBlock]()

    for service in request.services {
      let `protocol` = self.makeClientProtocol(for: service, in: request)
      blocks.append(.declaration(.commentable(.preFormatted(service.documentation), `protocol`)))

      let defaultImplementation = self.makeDefaultImplementation(for: service, in: request)
      blocks.append(.declaration(defaultImplementation))

      let sugaredAPI = self.makeSugaredAPI(forService: service, request: request)
      blocks.append(.declaration(sugaredAPI))

      let clientStruct = self.makeClientStruct(for: service, in: request)
      blocks.append(.declaration(.commentable(.preFormatted(service.documentation), clientStruct)))
    }

    return blocks
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
        includeBody: false,
        includeDefaultCallOptions: false
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
    return .guarded(self.availabilityGuard, clientProtocol)
  }

  private func makeDefaultImplementation(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let methods = service.methods.map {
      self.makeClientProtocolMethod(
        for: $0,
        in: service,
        from: codeGenerationRequest,
        includeBody: true,
        accessModifier: self.accessModifier,
        includeDefaultCallOptions: true
      )
    }
    let clientProtocolExtension = Declaration.extension(
      ExtensionDescription(
        onType: "\(service.namespacedGeneratedName).ClientProtocol",
        declarations: methods
      )
    )
    return .guarded(
      self.availabilityGuard,
      clientProtocolExtension
    )
  }

  private func makeSugaredAPI(
    forService service: CodeGenerationRequest.ServiceDescriptor,
    request: CodeGenerationRequest
  ) -> Declaration {
    let sugaredAPIExtension = Declaration.extension(
      ExtensionDescription(
        onType: "\(service.namespacedGeneratedName).ClientProtocol",
        declarations: service.methods.map { method in
          self.makeSugaredMethodDeclaration(
            method: method,
            accessModifier: self.accessModifier
          )
        }
      )
    )

    return .guarded(self.availabilityGuard, sugaredAPIExtension)
  }

  private func makeSugaredMethodDeclaration(
    method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    accessModifier: AccessModifier?
  ) -> Declaration {
    let signature = FunctionSignatureDescription(
      accessModifier: accessModifier,
      kind: .function(name: method.name.generatedLowerCase),
      generics: [.member("Result")],
      parameters: self.makeParametersForSugaredMethodDeclaration(method: method),
      keywords: [.async, .throws],
      returnType: .identifierPattern("Result"),
      whereClause: WhereClause(
        requirements: [
          .conformance("Result", "Sendable")
        ]
      )
    )

    let functionDescription = FunctionDescription(
      signature: signature,
      body: self.makeFunctionBodyForSugaredMethodDeclaration(method: method)
    )

    if method.documentation.isEmpty {
      return .function(functionDescription)
    } else {
      return .commentable(.preFormatted(method.documentation), .function(functionDescription))
    }
  }

  private func makeParametersForSugaredMethodDeclaration(
    method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  ) -> [ParameterDescription] {
    var parameters = [ParameterDescription]()

    // Unary inputs have a 'message' parameter
    if !method.isInputStreaming {
      parameters.append(
        ParameterDescription(
          label: "_",
          name: "message",
          type: .member([method.inputType])
        )
      )
    }

    parameters.append(
      ParameterDescription(
        label: "metadata",
        type: .member(["GRPCCore", "Metadata"]),
        defaultValue: .literal(.dictionary([]))
      )
    )

    parameters.append(
      ParameterDescription(
        label: "options",
        type: .member(["GRPCCore", "CallOptions"]),
        defaultValue: .memberAccess(.dot("defaults"))
      )
    )

    // Streaming inputs have a writer callback
    if method.isInputStreaming {
      parameters.append(
        ParameterDescription(
          label: "requestProducer",
          type: .closure(
            ClosureSignatureDescription(
              parameters: [
                ParameterDescription(
                  type: .generic(
                    wrapper: .member(["GRPCCore", "RPCWriter"]),
                    wrapped: .member(method.inputType)
                  )
                )
              ],
              keywords: [.async, .throws],
              returnType: .identifierPattern("Void"),
              sendable: true,
              escaping: true
            )
          )
        )
      )
    }

    // All methods have a response handler.
    var responseHandler = ParameterDescription(label: "onResponse", name: "handleResponse")
    let responseKind = method.isOutputStreaming ? "Stream" : "Single"
    responseHandler.type = .closure(
      ClosureSignatureDescription(
        parameters: [
          ParameterDescription(
            type: .generic(
              wrapper: .member(["GRPCCore", "ClientResponse", responseKind]),
              wrapped: .member(method.outputType)
            )
          )
        ],
        keywords: [.async, .throws],
        returnType: .identifierPattern("Result"),
        sendable: true,
        escaping: true
      )
    )

    if !method.isOutputStreaming {
      responseHandler.defaultValue = .closureInvocation(
        ClosureInvocationDescription(
          body: [.expression(.try(.identifierPattern("$0").dot("message")))]
        )
      )
    }

    parameters.append(responseHandler)

    return parameters
  }

  private func makeFunctionBodyForSugaredMethodDeclaration(
    method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  ) -> [CodeBlock] {
    // Produces the following:
    //
    // let request = GRPCCore.ClientRequest.Single<Input>(message: message, metadata: metadata)
    // return try await method(request: request, options: options, responseHandler: responseHandler)
    //
    // or:
    //
    // let request = GRPCCore.ClientRequest.Stream<Input>(metadata: metadata, producer: writer)
    // return try await method(request: request, options: options, responseHandler: responseHandler)

    // First, make the init for the ClientRequest
    let requestType = method.isInputStreaming ? "Stream" : "Single"
    var requestInit = FunctionCallDescription(
      calledExpression: .identifier(
        .type(
          .generic(
            wrapper: .member(["GRPCCore", "ClientRequest", requestType]),
            wrapped: .member(method.inputType)
          )
        )
      )
    )

    if method.isInputStreaming {
      requestInit.arguments.append(
        FunctionArgumentDescription(
          label: "metadata",
          expression: .identifierPattern("metadata")
        )
      )
      requestInit.arguments.append(
        FunctionArgumentDescription(
          label: "producer",
          expression: .identifierPattern("requestProducer")
        )
      )
    } else {
      requestInit.arguments.append(
        FunctionArgumentDescription(
          label: "message",
          expression: .identifierPattern("message")
        )
      )
      requestInit.arguments.append(
        FunctionArgumentDescription(
          label: "metadata",
          expression: .identifierPattern("metadata")
        )
      )
    }

    // Now declare the request:
    //
    // let request = <RequestInit>
    let request = VariableDescription(
      kind: .let,
      left: .identifier(.pattern("request")),
      right: .functionCall(requestInit)
    )

    var blocks = [CodeBlock]()
    blocks.append(.declaration(.variable(request)))

    // Finally, call the underlying method.
    let methodCall = FunctionCallDescription(
      calledExpression: .identifierPattern("self").dot(method.name.generatedLowerCase),
      arguments: [
        FunctionArgumentDescription(label: "request", expression: .identifierPattern("request")),
        FunctionArgumentDescription(label: "options", expression: .identifierPattern("options")),
        FunctionArgumentDescription(expression: .identifierPattern("handleResponse")),
      ]
    )

    blocks.append(.expression(.return(.try(.await(.functionCall(methodCall))))))
    return blocks
  }

  private func makeClientProtocolMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    from codeGenerationRequest: CodeGenerationRequest,
    includeBody: Bool,
    accessModifier: AccessModifier? = nil,
    includeDefaultCallOptions: Bool
  ) -> Declaration {
    let isProtocolExtension = includeBody
    let methodParameters = self.makeParameters(
      for: method,
      in: service,
      from: codeGenerationRequest,
      // The serializer/deserializer for the protocol extension method will be auto-generated.
      includeSerializationParameters: !isProtocolExtension,
      includeDefaultCallOptions: includeDefaultCallOptions,
      includeDefaultResponseHandler: isProtocolExtension && !method.isOutputStreaming
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

    if includeBody {
      let body = self.makeClientProtocolMethodCall(
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

  private func makeClientProtocolMethodCall(
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
          expression: .identifierPattern(codeGenerationRequest.lookupSerializer(method.inputType))
        ),
        FunctionArgumentDescription(
          label: "deserializer",
          expression: .identifierPattern(
            codeGenerationRequest.lookupDeserializer(method.outputType)
          )
        ),
        FunctionArgumentDescription(label: "options", expression: .identifierPattern("options")),
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
    includeSerializationParameters: Bool,
    includeDefaultCallOptions: Bool,
    includeDefaultResponseHandler: Bool
  ) -> [ParameterDescription] {
    var parameters = [ParameterDescription]()

    parameters.append(self.clientRequestParameter(for: method, in: service))
    if includeSerializationParameters {
      parameters.append(self.serializerParameter(for: method, in: service))
      parameters.append(self.deserializerParameter(for: method, in: service))
    }
    parameters.append(
      ParameterDescription(
        label: "options",
        type: .member("GRPCCore.CallOptions"),
        defaultValue: includeDefaultCallOptions
          ? .memberAccess(MemberAccessDescription(right: "defaults")) : nil
      )
    )
    parameters.append(
      self.bodyParameter(
        for: method,
        in: service,
        includeDefaultResponseHandler: includeDefaultResponseHandler
      )
    )
    return parameters
  }
  private func clientRequestParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor
  ) -> ParameterDescription {
    let requestType = method.isInputStreaming ? "Stream" : "Single"
    let clientRequestType = ExistingTypeDescription.member(["GRPCCore.ClientRequest", requestType])
    return ParameterDescription(
      label: "request",
      type: .generic(
        wrapper: clientRequestType,
        wrapped: .member(method.inputType)
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
          wrapper: .member("GRPCCore.MessageSerializer"),
          wrapped: .member(method.inputType)
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
          wrapper: .member("GRPCCore.MessageDeserializer"),
          wrapped: .member(method.outputType)
        )
      )
    )
  }

  private func bodyParameter(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    includeDefaultResponseHandler: Bool
  ) -> ParameterDescription {
    let clientStreaming = method.isOutputStreaming ? "Stream" : "Single"
    let closureParameterType = ExistingTypeDescription.generic(
      wrapper: .member(["GRPCCore.ClientResponse", clientStreaming]),
      wrapped: .member(method.outputType)
    )

    let bodyClosure = ClosureSignatureDescription(
      parameters: [.init(type: closureParameterType)],
      keywords: [.async, .throws],
      returnType: .identifierType(.member("R")),
      sendable: true,
      escaping: true
    )

    var defaultResponseHandler: Expression? = nil

    if includeDefaultResponseHandler {
      defaultResponseHandler = .closureInvocation(
        ClosureInvocationDescription(
          body: [.expression(.try(.identifierPattern("$0").dot("message")))]
        )
      )
    }

    return ParameterDescription(
      name: "body",
      type: .closure(bodyClosure),
      defaultValue: defaultResponseHandler
    )
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

    return .guarded(
      self.availabilityGuard,
      .struct(
        StructDescription(
          accessModifier: self.accessModifier,
          name: "\(service.namespacedGeneratedName)Client",
          conformances: ["\(service.namespacedGeneratedName).ClientProtocol"],
          members: [clientProperty, initializer] + methods
        )
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
        parameters: [
          .init(label: "wrapping", name: "client", type: .member(["GRPCCore", "GRPCClient"]))
        ]
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
      includeSerializationParameters: true,
      includeDefaultCallOptions: true,
      includeDefaultResponseHandler: !method.isOutputStreaming
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
            "\(service.namespacedGeneratedName).Method.\(method.name.generatedUpperCase).descriptor"
          )
        ),
        .init(label: "serializer", expression: .identifierPattern("serializer")),
        .init(label: "deserializer", expression: .identifierPattern("deserializer")),
        .init(label: "options", expression: .identifierPattern("options")),
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
}
