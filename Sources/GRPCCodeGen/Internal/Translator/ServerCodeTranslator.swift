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
/// one method "baz" with input type "Input" and output type "Output", the ``ServerCodeTranslator`` will create
/// a representation for the following generated code:
///
/// ```swift
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
///   func baz(
///     request: ServerRequest.Stream<Foo_Bar_Input>
///   ) async throws -> ServerResponse.Stream<Foo_Bar_Output>
/// }
/// // Conformance to `GRPCCore.RegistrableRPCService`.
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.StreamingServiceProtocol {
///   public func registerMethods(with router: inout GRPCCore.RPCRouter) {
///     router.registerHandler(
///       forMethod: Foo_Bar.Method.baz.descriptor,
///       deserializer: ProtobufDeserializer<Foo_Bar_Input>(),
///       serializer: ProtobufSerializer<Foo_Bar_Output>(),
///       handler: { request in try await self.baz(request: request) }
///     )
///   }
/// }
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// public protocol Foo_BarServiceProtocol: Foo_Bar.StreamingServiceProtocol {
///   func baz(
///     request: ServerRequest.Single<Foo_Bar_Input>
///   ) async throws -> ServerResponse.Single<Foo_Bar_Output>
/// }
/// // Partial conformance to `Foo_BarStreamingServiceProtocol`.
/// @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
/// extension Foo_Bar.ServiceProtocol {
///   public func baz(
///     request: ServerRequest.Stream<Foo_Bar_Input>
///   ) async throws -> ServerResponse.Stream<Foo_Bar_Output> {
///     let response = try await self.baz(request: ServerRequest.Single(stream: request))
///     return ServerResponse.Stream(single: response)
///   }
/// }
///```
struct ServerCodeTranslator: SpecializedTranslator {
  var accessLevel: SourceGenerator.Configuration.AccessLevel

  init(accessLevel: SourceGenerator.Configuration.AccessLevel) {
    self.accessLevel = accessLevel
  }

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
        .preFormatted($0.documentation),
        .function(
          FunctionDescription(
            signature: self.makeStreamingMethodSignature(for: $0, in: service)
          )
        )
      )
    }

    let streamingProtocol = Declaration.protocol(
      .init(
        accessModifier: self.accessModifier,
        name: self.protocolName(service: service, streaming: true),
        conformances: ["GRPCCore.RegistrableRPCService"],
        members: methods
      )
    )

    return .commentable(
      .preFormatted(service.documentation),
      .guarded(self.availabilityGuard, streamingProtocol)
    )
  }

  private func makeStreamingMethodSignature(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    accessModifier: AccessModifier? = nil
  ) -> FunctionSignatureDescription {
    return FunctionSignatureDescription(
      accessModifier: accessModifier,
      kind: .function(name: method.name.generatedLowerCase),
      parameters: [
        .init(
          label: "request",
          type: .generic(
            wrapper: .member(["ServerRequest", "Stream"]),
            wrapped: .member(method.inputType)
          )
        )
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(
        .generic(
          wrapper: .member(["ServerResponse", "Stream"]),
          wrapped: .member(method.outputType)
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
    return .guarded(
      self.availabilityGuard,
      .extension(
        onType: streamingProtocol,
        declarations: [registerRPCMethod]
      )
    )
  }

  private func makeRegisterRPCsMethod(
    for service: CodeGenerationRequest.ServiceDescriptor,
    in codeGenerationRequest: CodeGenerationRequest
  ) -> Declaration {
    let registerRPCsSignature = FunctionSignatureDescription(
      accessModifier: self.accessModifier,
      kind: .function(name: "registerMethods"),
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
    return .guarded(
      self.availabilityGuard,
      .function(signature: registerRPCsSignature, body: registerRPCsBody)
    )
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
        label: "forMethod",
        expression: .identifierPattern(
          self.methodDescriptorPath(for: method, service: service)
        )
      )
    )

    arguments.append(
      .init(
        label: "deserializer",
        expression: .identifierPattern(codeGenerationRequest.lookupDeserializer(method.inputType))
      )
    )

    arguments.append(
      .init(
        label: "serializer",
        expression:
          .identifierPattern(codeGenerationRequest.lookupSerializer(method.outputType))
      )
    )

    let getFunctionCall = Expression.functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(
          left: .identifierPattern("self"),
          right: method.name.generatedLowerCase
        )
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
      .preFormatted(service.documentation),
      .guarded(
        self.availabilityGuard,
        .protocol(
          ProtocolDescription(
            accessModifier: self.accessModifier,
            name: protocolName,
            conformances: [streamingProtocol],
            members: methods
          )
        )
      )
    )
  }

  private func makeServiceProtocolMethod(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    in service: CodeGenerationRequest.ServiceDescriptor,
    accessModifier: AccessModifier? = nil
  ) -> Declaration {
    let inputStreaming = method.isInputStreaming ? "Stream" : "Single"
    let outputStreaming = method.isOutputStreaming ? "Stream" : "Single"

    let functionSignature = FunctionSignatureDescription(
      accessModifier: accessModifier,
      kind: .function(name: method.name.generatedLowerCase),
      parameters: [
        .init(
          label: "request",
          type:
            .generic(
              wrapper: .member(["ServerRequest", inputStreaming]),
              wrapped: .member(method.inputType)
            )
        )
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(
        .generic(
          wrapper: .member(["ServerResponse", outputStreaming]),
          wrapped: .member(method.outputType)
        )
      )
    )

    return .commentable(
      .preFormatted(method.documentation),
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
    return .guarded(
      self.availabilityGuard,
      .extension(
        onType: protocolName,
        declarations: methods
      )
    )
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
      signature: self.makeStreamingMethodSignature(
        for: method,
        in: service,
        accessModifier: self.accessModifier
      ),
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
        MemberAccessDescription(
          left: .identifierPattern("self"),
          right: method.name.generatedLowerCase
        )
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

  /// Generates the fully qualified name of a method descriptor.
  private func methodDescriptorPath(
    for method: CodeGenerationRequest.ServiceDescriptor.MethodDescriptor,
    service: CodeGenerationRequest.ServiceDescriptor
  ) -> String {
    return
      "\(service.namespacedGeneratedName).Method.\(method.name.generatedUpperCase).descriptor"
  }

  /// Generates the fully qualified name of the type alias for a service protocol.
  internal func protocolNameTypealias(
    service: CodeGenerationRequest.ServiceDescriptor,
    streaming: Bool
  ) -> String {
    if streaming {
      return "\(service.namespacedGeneratedName).StreamingServiceProtocol"
    }
    return "\(service.namespacedGeneratedName).ServiceProtocol"
  }

  /// Generates the name of a service protocol.
  internal func protocolName(
    service: CodeGenerationRequest.ServiceDescriptor,
    streaming: Bool
  ) -> String {
    if streaming {
      return "\(service.namespacedGeneratedName)StreamingServiceProtocol"
    }
    return "\(service.namespacedGeneratedName)ServiceProtocol"
  }
}
