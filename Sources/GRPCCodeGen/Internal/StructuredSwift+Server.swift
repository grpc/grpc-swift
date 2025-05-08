/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

extension FunctionSignatureDescription {
  /// ```
  /// func <Method>(
  ///   request: GRPCCore.ServerRequest<Input>,
  ///   context: GRPCCore.ServerContext
  /// ) async throws -> GRPCCore.ServerResponse<Output>
  /// ```
  static func serverMethod(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    namer: Namer = Namer()
  ) -> Self {
    return FunctionSignatureDescription(
      accessModifier: accessLevel,
      kind: .function(name: name),
      parameters: [
        ParameterDescription(
          label: "request",
          type: namer.serverRequest(forType: input, isStreaming: streamingInput)
        ),
        ParameterDescription(label: "context", type: namer.serverContext),
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(
        namer.serverResponse(forType: output, isStreaming: streamingOutput)
      )
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ProtocolDescription {
  /// ```
  /// protocol <Name>: GRPCCore.RegistrableRPCService {
  ///   ...
  /// }
  /// ```
  static func streamingService(
    accessLevel: AccessModifier? = nil,
    name: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer()
  ) -> Self {
    func docs(for method: MethodDescriptor) -> String {
      let summary = """
        /// Handle the "\(method.name.identifyingName)" method.
        """

      let parameters = """
        /// - Parameters:
        ///   - request: A streaming request of `\(method.inputType)` messages.
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        /// - Returns: A streaming response of `\(method.outputType)` messages.
        """

      return Docs.interposeDocs(method.documentation, between: summary, and: parameters)
    }

    return ProtocolDescription(
      accessModifier: accessLevel,
      name: name,
      conformances: [namer.literalNamespacedType("RegistrableRPCService")],
      members: methods.map { method in
        .commentable(
          .preFormatted(docs(for: method)),
          .function(
            signature: .serverMethod(
              name: method.name.functionName,
              input: method.inputType,
              output: method.outputType,
              streamingInput: true,
              streamingOutput: true,
              namer: namer
            )
          )
        )
      }
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ExtensionDescription {
  /// ```
  /// extension <ExtensionName> {
  ///   func registerMethods(with router: inout GRPCCore.RPCRouter) {
  ///     // ...
  ///   }
  /// }
  /// ```
  static func registrableRPCServiceDefaultImplementation(
    accessLevel: AccessModifier? = nil,
    on extensionName: String,
    serviceNamespace: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer(),
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> Self {
    return ExtensionDescription(
      onType: extensionName,
      declarations: [
        .function(
          .registerMethods(
            accessLevel: accessLevel,
            serviceNamespace: serviceNamespace,
            methods: methods,
            namer: namer,
            serializer: serializer,
            deserializer: deserializer
          )
        )
      ]
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ProtocolDescription {
  /// ```
  /// protocol <Name>: <StreamingProtocol> {
  ///   ...
  /// }
  /// ```
  static func service(
    accessLevel: AccessModifier? = nil,
    name: String,
    streamingProtocol: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer()
  ) -> Self {
    func docs(for method: MethodDescriptor) -> String {
      let summary = """
        /// Handle the "\(method.name.identifyingName)" method.
        """

      let request: String
      if method.isInputStreaming {
        request = "A streaming request of `\(method.inputType)` messages."
      } else {
        request = "A request containing a single `\(method.inputType)` message."
      }

      let returns: String
      if method.isOutputStreaming {
        returns = "A streaming response of `\(method.outputType)` messages."
      } else {
        returns = "A response containing a single `\(method.outputType)` message."
      }

      let parameters = """
        /// - Parameters:
        ///   - request: \(request)
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        /// - Returns: \(returns)
        """

      return Docs.interposeDocs(method.documentation, between: summary, and: parameters)
    }

    return ProtocolDescription(
      accessModifier: accessLevel,
      name: name,
      conformances: [streamingProtocol],
      members: methods.map { method in
        .commentable(
          .preFormatted(docs(for: method)),
          .function(
            signature: .serverMethod(
              name: method.name.functionName,
              input: method.inputType,
              output: method.outputType,
              streamingInput: method.isInputStreaming,
              streamingOutput: method.isOutputStreaming,
              namer: namer
            )
          )
        )
      }
    )
  }
}

extension FunctionCallDescription {
  /// ```
  /// self.<Name>(request: request, context: context)
  /// ```
  static func serverMethodCallOnSelf(
    name: String,
    requestArgument: Expression = .identifierPattern("request")
  ) -> Self {
    return FunctionCallDescription(
      calledExpression: .memberAccess(
        MemberAccessDescription(
          left: .identifierPattern("self"),
          right: name
        )
      ),
      arguments: [
        FunctionArgumentDescription(
          label: "request",
          expression: requestArgument
        ),
        FunctionArgumentDescription(
          label: "context",
          expression: .identifierPattern("context")
        ),
      ]
    )
  }
}

extension ClosureInvocationDescription {
  /// ```
  /// { router, context in
  ///   try await self.<Method>(
  ///     request: request,
  ///     context: context
  ///   )
  /// }
  /// ```
  static func routerHandlerInvokingRPC(method: String) -> Self {
    return ClosureInvocationDescription(
      argumentNames: ["request", "context"],
      body: [
        .expression(
          .unaryKeyword(
            kind: .try,
            expression: .unaryKeyword(
              kind: .await,
              expression: .functionCall(.serverMethodCallOnSelf(name: method))
            )
          )
        )
      ]
    )
  }
}

/// ```
/// router.registerHandler(
///   forMethod: ...,
///   deserializer: ...
///   serializer: ...
///   handler: { request, context in
///     // ...
///   }
/// )
/// ```
extension FunctionCallDescription {
  static func registerWithRouter(
    serviceNamespace: String,
    methodNamespace: String,
    methodName: String,
    inputDeserializer: String,
    outputSerializer: String
  ) -> Self {
    return FunctionCallDescription(
      calledExpression: .memberAccess(
        .init(left: .identifierPattern("router"), right: "registerHandler")
      ),
      arguments: [
        FunctionArgumentDescription(
          label: "forMethod",
          expression: .identifierPattern("\(serviceNamespace).Method.\(methodNamespace).descriptor")
        ),
        FunctionArgumentDescription(
          label: "deserializer",
          expression: .identifierPattern(inputDeserializer)
        ),
        FunctionArgumentDescription(
          label: "serializer",
          expression: .identifierPattern(outputSerializer)
        ),
        FunctionArgumentDescription(
          label: "handler",
          expression: .closureInvocation(.routerHandlerInvokingRPC(method: methodName))
        ),
      ]
    )
  }
}

@available(gRPCSwift 2.0, *)
extension FunctionDescription {
  /// ```
  /// func registerMethods(with router: inout GRPCCore.RPCRouter) {
  ///   // ...
  /// }
  /// ```
  static func registerMethods(
    accessLevel: AccessModifier? = nil,
    serviceNamespace: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer(),
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> Self {
    return FunctionDescription(
      accessModifier: accessLevel,
      kind: .function(name: "registerMethods"),
      generics: [.member("Transport")],
      parameters: [
        ParameterDescription(
          label: "with",
          name: "router",
          type: namer.rpcRouter(genericOver: "Transport"),
          `inout`: true
        )
      ],
      whereClause: WhereClause(
        requirements: [
          .conformance("Transport", namer.literalNamespacedType("ServerTransport"))
        ]
      ),
      body: methods.map { method in
        .functionCall(
          .registerWithRouter(
            serviceNamespace: serviceNamespace,
            methodNamespace: method.name.typeName,
            methodName: method.name.functionName,
            inputDeserializer: deserializer(method.inputType),
            outputSerializer: serializer(method.outputType)
          )
        )
      }
    )
  }
}

extension FunctionDescription {
  /// ```
  /// func <Name>(
  ///   request: GRPCCore.StreamingServerRequest<Input>
  ///   context: GRPCCore.ServerContext
  /// ) async throws -> GRPCCore.StreamingServerResponse<Output> {
  ///   let response = try await self.<Name>(
  ///     request: GRPCCore.ServerRequest(stream: request),
  ///     context: context
  ///   )
  ///   return GRPCCore.StreamingServerResponse(single: response)
  /// }
  /// ```
  static func serverStreamingMethodsCallingMethod(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    namer: Namer = Namer()
  ) -> FunctionDescription {
    let signature: FunctionSignatureDescription = .serverMethod(
      accessLevel: accessLevel,
      name: name,
      input: input,
      output: output,
      // This method converts from the fully streamed version to the specified version.
      streamingInput: true,
      streamingOutput: true,
      namer: namer
    )

    // Call the underlying function.
    let functionCall: Expression = .functionCall(
      calledExpression: .memberAccess(
        MemberAccessDescription(
          left: .identifierPattern("self"),
          right: name
        )
      ),
      arguments: [
        FunctionArgumentDescription(
          label: "request",
          expression: streamingInput
            ? .identifierPattern("request")
            : .functionCall(
              calledExpression: .identifierType(
                namer.serverRequest(forType: nil, isStreaming: false)
              ),
              arguments: [
                FunctionArgumentDescription(
                  label: "stream",
                  expression: .identifierPattern("request")
                )
              ]
            )
        ),
        FunctionArgumentDescription(
          label: "context",
          expression: .identifierPattern("context")
        ),
      ]
    )

    // Call the function and assign to 'response'.
    let response: Declaration = .variable(
      kind: .let,
      left: "response",
      right: .unaryKeyword(
        kind: .try,
        expression: .unaryKeyword(
          kind: .await,
          expression: functionCall
        )
      )
    )

    // Build the return statement.
    let returnExpression: Expression = .unaryKeyword(
      kind: .return,
      expression: streamingOutput
        ? .identifierPattern("response")
        : .functionCall(
          calledExpression: .identifierType(namer.serverResponse(forType: nil, isStreaming: true)),
          arguments: [
            FunctionArgumentDescription(
              label: "single",
              expression: .identifierPattern("response")
            )
          ]
        )
    )

    return Self(
      signature: signature,
      body: [.declaration(response), .expression(returnExpression)]
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ExtensionDescription {
  /// ```
  /// extension <ExtensionName> {
  ///   func <Name>(
  ///     request: GRPCCore.StreamingServerRequest<Input>
  ///     context: GRPCCore.ServerContext
  ///   ) async throws -> GRPCCore.StreamingServerResponse<Output> {
  ///     let response = try await self.<Name>(
  ///       request: GRPCCore.ServerRequest(stream: request),
  ///       context: context
  ///     )
  ///     return GRPCCore.StreamingServerResponse(single: response)
  ///   }
  ///   ...
  /// }
  /// ```
  static func streamingServiceProtocolDefaultImplementation(
    accessModifier: AccessModifier? = nil,
    on extensionName: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer()
  ) -> Self {
    return ExtensionDescription(
      onType: extensionName,
      declarations: methods.compactMap { method -> Declaration? in
        // Bidirectional streaming methods don't need a default implementation as their signatures
        // match across the two protocols.
        if method.isInputStreaming, method.isOutputStreaming { return nil }

        return .function(
          .serverStreamingMethodsCallingMethod(
            accessLevel: accessModifier,
            name: method.name.functionName,
            input: method.inputType,
            output: method.outputType,
            streamingInput: method.isInputStreaming,
            streamingOutput: method.isOutputStreaming,
            namer: namer
          )
        )
      }
    )
  }
}

extension FunctionSignatureDescription {
  /// ```
  /// func <Name>(
  ///   request: <Input>,
  ///   context: GRPCCore.ServerContext,
  /// ) async throws -> <Output>
  /// ```
  ///
  /// ```
  /// func <Name>(
  ///   request: GRPCCore.RPCAsyncSequence<Input, any Error>,
  ///   response: GRPCCore.RPCAsyncWriter<Output>
  ///   context: GRPCCore.ServerContext,
  /// ) async throws
  /// ```
  static func simpleServerMethod(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    namer: Namer = Namer()
  ) -> Self {
    var parameters: [ParameterDescription] = [
      ParameterDescription(
        label: "request",
        type: streamingInput ? namer.rpcAsyncSequence(forType: input) : .member(input)
      )
    ]

    if streamingOutput {
      parameters.append(
        ParameterDescription(
          label: "response",
          type: namer.rpcWriter(forType: output)
        )
      )
    }

    parameters.append(ParameterDescription(label: "context", type: namer.serverContext))

    return FunctionSignatureDescription(
      accessModifier: accessLevel,
      kind: .function(name: name),
      parameters: parameters,
      keywords: [.async, .throws],
      returnType: streamingOutput ? nil : .identifier(.pattern(output))
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ProtocolDescription {
  /// ```
  /// protocol SimpleServiceProtocol: <ServiceProtocol> {
  ///   ...
  /// }
  /// ```
  static func simpleServiceProtocol(
    accessModifier: AccessModifier? = nil,
    name: String,
    serviceProtocol: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer()
  ) -> Self {
    func docs(for method: MethodDescriptor) -> String {
      let summary = """
        /// Handle the "\(method.name.identifyingName)" method.
        """

      let requestText =
        method.isInputStreaming
        ? "A stream of `\(method.inputType)` messages."
        : "A `\(method.inputType)` message."

      var parameters = """
        /// - Parameters:
        ///   - request: \(requestText)
        """

      if method.isOutputStreaming {
        parameters += "\n"
        parameters += """
          ///   - response: A response stream of `\(method.outputType)` messages.
          """
      }

      parameters += "\n"
      parameters += """
        ///   - context: Context providing information about the RPC.
        /// - Throws: Any error which occurred during the processing of the request. Thrown errors
        ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
        ///     to an internal error.
        """

      if !method.isOutputStreaming {
        parameters += "\n"
        parameters += """
          /// - Returns: A `\(method.outputType)` to respond with.
          """
      }

      return Docs.interposeDocs(method.documentation, between: summary, and: parameters)
    }

    return ProtocolDescription(
      accessModifier: accessModifier,
      name: name,
      conformances: [serviceProtocol],
      members: methods.map { method in
        .commentable(
          .preFormatted(docs(for: method)),
          .function(
            signature: .simpleServerMethod(
              name: method.name.functionName,
              input: method.inputType,
              output: method.outputType,
              streamingInput: method.isInputStreaming,
              streamingOutput: method.isOutputStreaming,
              namer: namer
            )
          )
        )
      }
    )
  }
}

extension FunctionCallDescription {
  /// ```
  /// try await self.<Name>(
  ///   request: request.message,
  ///   response: writer,
  ///   context: context
  /// )
  /// ```
  static func serviceMethodCallingSimpleMethod(
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool
  ) -> Self {
    var arguments: [FunctionArgumentDescription] = [
      FunctionArgumentDescription(
        label: "request",
        expression: .identifierPattern("request").dot(streamingInput ? "messages" : "message")
      )
    ]

    if streamingOutput {
      arguments.append(
        FunctionArgumentDescription(
          label: "response",
          expression: .identifierPattern("writer")
        )
      )
    }

    arguments.append(
      FunctionArgumentDescription(
        label: "context",
        expression: .identifierPattern("context")
      )
    )

    return FunctionCallDescription(
      calledExpression: .try(.await(.identifierPattern("self").dot(name))),
      arguments: arguments
    )
  }
}

extension FunctionDescription {
  /// ```
  /// func <Name>(
  ///   request: GRPCCore.ServerRequest<Input>,
  ///   context: GRPCCore.ServerContext
  /// ) async throws -> GRPCCore.ServerResponse<Output> {
  ///   return GRPCCore.ServerResponse<Output>(
  ///     message: try await self.<Name>(
  ///       request: request.message,
  ///       context: context
  ///     )
  ///     metadata: [:]
  ///   )
  /// }
  /// ```
  static func serviceProtocolDefaultImplementation(
    accessModifier: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    namer: Namer = Namer()
  ) -> Self {
    func makeUnaryOutputArguments() -> [FunctionArgumentDescription] {
      return [
        FunctionArgumentDescription(
          label: "message",
          expression: .functionCall(
            .serviceMethodCallingSimpleMethod(
              name: name,
              input: input,
              output: output,
              streamingInput: streamingInput,
              streamingOutput: streamingOutput
            )
          )
        ),
        FunctionArgumentDescription(label: "metadata", expression: .literal(.dictionary([]))),
      ]
    }

    func makeStreamingOutputArguments() -> [FunctionArgumentDescription] {
      return [
        FunctionArgumentDescription(label: "metadata", expression: .literal(.dictionary([]))),
        FunctionArgumentDescription(
          label: "producer",
          expression: .closureInvocation(
            argumentNames: ["writer"],
            body: [
              .expression(
                .functionCall(
                  .serviceMethodCallingSimpleMethod(
                    name: name,
                    input: input,
                    output: output,
                    streamingInput: streamingInput,
                    streamingOutput: streamingOutput
                  )
                )
              ),
              .expression(.return(.literal(.dictionary([])))),
            ]
          )
        ),
      ]
    }

    return FunctionDescription(
      signature: .serverMethod(
        accessLevel: accessModifier,
        name: name,
        input: input,
        output: output,
        streamingInput: streamingInput,
        streamingOutput: streamingOutput,
        namer: namer
      ),
      body: [
        .expression(
          .functionCall(
            calledExpression: .return(
              .identifierType(
                namer.serverResponse(forType: output, isStreaming: streamingOutput)
              )
            ),
            arguments: streamingOutput ? makeStreamingOutputArguments() : makeUnaryOutputArguments()
          )
        )
      ]
    )
  }
}

@available(gRPCSwift 2.0, *)
extension ExtensionDescription {
  /// ```
  /// extension ServiceProtocol {
  ///   ...
  /// }
  /// ```
  static func serviceProtocolDefaultImplementation(
    accessModifier: AccessModifier? = nil,
    on extensionName: String,
    methods: [MethodDescriptor],
    namer: Namer = Namer()
  ) -> Self {
    ExtensionDescription(
      onType: extensionName,
      declarations: methods.map { method in
        .function(
          .serviceProtocolDefaultImplementation(
            accessModifier: accessModifier,
            name: method.name.functionName,
            input: method.inputType,
            output: method.outputType,
            streamingInput: method.isInputStreaming,
            streamingOutput: method.isOutputStreaming,
            namer: namer
          )
        )
      }
    )
  }
}
