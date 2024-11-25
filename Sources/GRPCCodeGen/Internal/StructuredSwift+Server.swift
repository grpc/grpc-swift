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
    streamingOutput: Bool
  ) -> Self {
    return FunctionSignatureDescription(
      accessModifier: accessLevel,
      kind: .function(name: name),
      parameters: [
        ParameterDescription(
          label: "request",
          type: .serverRequest(forType: input, streaming: streamingInput)
        ),
        ParameterDescription(label: "context", type: .serverContext),
      ],
      keywords: [.async, .throws],
      returnType: .identifierType(.serverResponse(forType: output, streaming: streamingOutput))
    )
  }
}

extension ProtocolDescription {
  /// ```
  /// protocol <Name>: GRPCCore.RegistrableRPCService {
  ///   ...
  /// }
  /// ```
  static func streamingService(
    accessLevel: AccessModifier? = nil,
    name: String,
    methods: [MethodDescriptor]
  ) -> Self {
    return ProtocolDescription(
      accessModifier: accessLevel,
      name: name,
      conformances: ["GRPCCore.RegistrableRPCService"],
      members: methods.map { method in
        .commentable(
          .preFormatted(method.documentation),
          .function(
            signature: .serverMethod(
              name: method.name.generatedLowerCase,
              input: method.inputType,
              output: method.outputType,
              streamingInput: true,
              streamingOutput: true
            )
          )
        )
      }
    )
  }
}

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
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> Self {
    return ExtensionDescription(
      onType: extensionName,
      declarations: [
        .guarded(
          .grpc,
          .function(
            .registerMethods(
              accessLevel: accessLevel,
              serviceNamespace: serviceNamespace,
              methods: methods,
              serializer: serializer,
              deserializer: deserializer
            )
          )
        )
      ]
    )
  }
}

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
    methods: [MethodDescriptor]
  ) -> Self {
    return ProtocolDescription(
      accessModifier: accessLevel,
      name: name,
      conformances: [streamingProtocol],
      members: methods.map { method in
        .commentable(
          .preFormatted(method.documentation),
          .function(
            signature: .serverMethod(
              name: method.name.generatedLowerCase,
              input: method.inputType,
              output: method.outputType,
              streamingInput: method.isInputStreaming,
              streamingOutput: method.isOutputStreaming
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
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> Self {
    return FunctionDescription(
      accessModifier: accessLevel,
      kind: .function(name: "registerMethods"),
      parameters: [
        ParameterDescription(
          label: "with",
          name: "router",
          type: .rpcRouter,
          `inout`: true
        )
      ],
      body: methods.map { method in
        .functionCall(
          .registerWithRouter(
            serviceNamespace: serviceNamespace,
            methodNamespace: method.name.generatedUpperCase,
            methodName: method.name.generatedLowerCase,
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
    streamingOutput: Bool
  ) -> FunctionDescription {
    let signature: FunctionSignatureDescription = .serverMethod(
      accessLevel: accessLevel,
      name: name,
      input: input,
      output: output,
      // This method converts from the fully streamed version to the specified version.
      streamingInput: true,
      streamingOutput: true
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
              calledExpression: .identifierType(.serverRequest(forType: nil, streaming: false)),
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
          calledExpression: .identifierType(.serverResponse(forType: nil, streaming: true)),
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
    methods: [MethodDescriptor]
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
            name: method.name.generatedLowerCase,
            input: method.inputType,
            output: method.outputType,
            streamingInput: method.isInputStreaming,
            streamingOutput: method.isOutputStreaming
          )
        )
      }
    )
  }
}
