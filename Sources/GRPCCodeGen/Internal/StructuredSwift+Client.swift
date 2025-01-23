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

extension ClosureInvocationDescription {
  /// ```
  /// { response in
  ///   try response.message
  /// }
  /// ```
  static var defaultClientUnaryResponseHandler: Self {
    ClosureInvocationDescription(
      argumentNames: ["response"],
      body: [.expression(.try(.identifierPattern("response").dot("message")))]
    )
  }
}

extension FunctionSignatureDescription {
  /// ```
  /// func <Name><Result>(
  ///   request: GRPCCore.ClientRequest<Input>,
  ///   serializer: some GRPCCore.MessageSerializer<Input>,
  ///   deserializer: some GRPCCore.MessageDeserializer<Output>,
  ///   options: GRPCCore.CallOptions,
  ///   onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Input>) async throws -> Result
  /// ) async throws -> Result where Result: Sendable
  /// ```
  static func clientMethod(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    includeDefaults: Bool,
    includeSerializers: Bool
  ) -> Self {
    var signature = FunctionSignatureDescription(
      accessModifier: accessLevel,
      kind: .function(name: name, isStatic: false),
      generics: [.member("Result")],
      parameters: [],  // Populated below.
      keywords: [.async, .throws],
      returnType: .identifierPattern("Result"),
      whereClause: WhereClause(requirements: [.conformance("Result", "Sendable")])
    )

    signature.parameters.append(
      ParameterDescription(
        label: "request",
        type: .clientRequest(forType: input, streaming: streamingInput)
      )
    )

    if includeSerializers {
      signature.parameters.append(
        ParameterDescription(
          label: "serializer",
          // Type is optional, so be explicit about which 'some' to use
          type: ExistingTypeDescription.some(.serializer(forType: input))
        )
      )
      signature.parameters.append(
        ParameterDescription(
          label: "deserializer",
          // Type is optional, so be explicit about which 'some' to use
          type: ExistingTypeDescription.some(.deserializer(forType: output))
        )
      )
    }

    signature.parameters.append(
      ParameterDescription(
        label: "options",
        type: .callOptions,
        defaultValue: includeDefaults ? .memberAccess(.dot("defaults")) : nil
      )
    )

    signature.parameters.append(
      ParameterDescription(
        label: "onResponse",
        name: "handleResponse",
        type: .closure(
          ClosureSignatureDescription(
            parameters: [
              ParameterDescription(
                type: .clientResponse(forType: output, streaming: streamingOutput)
              )
            ],
            keywords: [.async, .throws],
            returnType: .identifierPattern("Result"),
            sendable: true,
            escaping: true
          )
        ),
        defaultValue: includeDefaults && !streamingOutput
          ? .closureInvocation(.defaultClientUnaryResponseHandler)
          : nil
      )
    )

    return signature
  }
}

extension FunctionDescription {
  /// ```
  /// func <Name><Result>(
  ///   request: GRPCCore.ClientRequest<Input>,
  ///   options: GRPCCore.CallOptions = .defaults,
  ///   onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Input>) async throws -> Result
  /// ) async throws -> Result where Result: Sendable {
  ///   try await self.<Name>(
  ///     request: request,
  ///     serializer: <Serializer>,
  ///     deserializer: <Deserializer>,
  ///     options: options
  ///     onResponse: handleResponse,
  ///   )
  /// }
  /// ```
  static func clientMethodWithDefaults(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool,
    serializer: Expression,
    deserializer: Expression
  ) -> Self {
    FunctionDescription(
      signature: .clientMethod(
        accessLevel: accessLevel,
        name: name,
        input: input,
        output: output,
        streamingInput: streamingInput,
        streamingOutput: streamingOutput,
        includeDefaults: true,
        includeSerializers: false
      ),
      body: [
        .expression(
          .try(
            .await(
              .functionCall(
                calledExpression: .identifierPattern("self").dot(name),
                arguments: [
                  FunctionArgumentDescription(
                    label: "request",
                    expression: .identifierPattern("request")
                  ),
                  FunctionArgumentDescription(
                    label: "serializer",
                    expression: serializer
                  ),
                  FunctionArgumentDescription(
                    label: "deserializer",
                    expression: deserializer
                  ),
                  FunctionArgumentDescription(
                    label: "options",
                    expression: .identifierPattern("options")
                  ),
                  FunctionArgumentDescription(
                    label: "onResponse",
                    expression: .identifierPattern("handleResponse")
                  ),
                ]
              )
            )
          )
        )
      ]
    )
  }
}

extension ProtocolDescription {
  /// ```
  /// protocol <Name>: Sendable {
  ///   func foo<Result: Sendable>(
  ///     ...
  ///   ) async throws -> Result
  /// }
  /// ```
  static func clientProtocol(
    accessLevel: AccessModifier? = nil,
    name: String,
    methods: [MethodDescriptor]
  ) -> Self {
    ProtocolDescription(
      accessModifier: accessLevel,
      name: name,
      conformances: ["Sendable"],
      members: methods.map { method in
        .commentable(
          .preFormatted(docs(for: method)),
          .function(
            signature: .clientMethod(
              name: method.name.functionName,
              input: method.inputType,
              output: method.outputType,
              streamingInput: method.isInputStreaming,
              streamingOutput: method.isOutputStreaming,
              includeDefaults: false,
              includeSerializers: true
            )
          )
        )
      }
    )
  }
}

extension ExtensionDescription {
  /// ```
  /// extension <Name> {
  ///   func foo<Result: Sendable>(
  ///     request: GRPCCore.ClientRequest<Input>,
  ///     options: GRPCCore.CallOptions = .defaults,
  ///     onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Input>) async throws -> Result
  ///   ) async throws -> Result where Result: Sendable {
  ///     // ...
  ///   }
  ///   // ...
  /// }
  /// ```
  static func clientMethodSignatureWithDefaults(
    accessLevel: AccessModifier? = nil,
    name: String,
    methods: [MethodDescriptor],
    serializer: (String) -> String,
    deserializer: (String) -> String
  ) -> Self {
    ExtensionDescription(
      onType: name,
      declarations: methods.map { method in
        .commentable(
          .preFormatted(docs(for: method, serializers: false)),
          .function(
            .clientMethodWithDefaults(
              accessLevel: accessLevel,
              name: method.name.functionName,
              input: method.inputType,
              output: method.outputType,
              streamingInput: method.isInputStreaming,
              streamingOutput: method.isOutputStreaming,
              serializer: .identifierPattern(serializer(method.inputType)),
              deserializer: .identifierPattern(deserializer(method.outputType))
            )
          )
        )
      }
    )
  }
}

extension FunctionSignatureDescription {
  /// ```
  /// func foo<Result>(
  ///   _ message: <Input>,
  ///   metadata: GRPCCore.Metadata = [:],
  ///   options: GRPCCore.CallOptions = .defaults,
  ///   onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
  ///     try response.message
  ///   }
  /// ) async throws -> Result where Result: Sendable
  /// ```
  static func clientMethodExploded(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool
  ) -> Self {
    var signature = FunctionSignatureDescription(
      accessModifier: accessLevel,
      kind: .function(name: name),
      generics: [.member("Result")],
      parameters: [],  // Populated below
      keywords: [.async, .throws],
      returnType: .identifierPattern("Result"),
      whereClause: WhereClause(requirements: [.conformance("Result", "Sendable")])
    )

    if !streamingInput {
      signature.parameters.append(
        ParameterDescription(label: "_", name: "message", type: .member(input))
      )
    }

    // metadata: GRPCCore.Metadata = [:]
    signature.parameters.append(
      ParameterDescription(
        label: "metadata",
        type: .metadata,
        defaultValue: .literal(.dictionary([]))
      )
    )

    // options: GRPCCore.CallOptions = .defaults
    signature.parameters.append(
      ParameterDescription(
        label: "options",
        type: .callOptions,
        defaultValue: .dot("defaults")
      )
    )

    if streamingInput {
      signature.parameters.append(
        ParameterDescription(
          label: "requestProducer",
          name: "producer",
          type: .closure(
            ClosureSignatureDescription(
              parameters: [ParameterDescription(type: .rpcWriter(forType: input))],
              keywords: [.async, .throws],
              returnType: .identifierPattern("Void"),
              sendable: true,
              escaping: true
            )
          )
        )
      )
    }

    signature.parameters.append(
      ParameterDescription(
        label: "onResponse",
        name: "handleResponse",
        type: .closure(
          ClosureSignatureDescription(
            parameters: [
              ParameterDescription(
                type: .clientResponse(forType: output, streaming: streamingOutput)
              )
            ],
            keywords: [.async, .throws],
            returnType: .identifierPattern("Result"),
            sendable: true,
            escaping: true
          )
        ),
        defaultValue: streamingOutput ? nil : .closureInvocation(.defaultClientUnaryResponseHandler)
      )
    )

    return signature
  }
}

extension [CodeBlock] {
  /// ```
  /// let request = GRPCCore.StreamingClientRequest<Input>(
  ///   metadata: metadata,
  ///   producer: producer
  /// )
  /// return try await self.foo(
  ///   request: request,
  ///   options: options,
  ///   onResponse: handleResponse
  /// )
  /// ```
  static func clientMethodExploded(
    name: String,
    input: String,
    streamingInput: Bool
  ) -> Self {
    func arguments(streaming: Bool) -> [FunctionArgumentDescription] {
      let metadata = FunctionArgumentDescription(
        label: "metadata",
        expression: .identifierPattern("metadata")
      )

      if streaming {
        return [
          metadata,
          FunctionArgumentDescription(
            label: "producer",
            expression: .identifierPattern("producer")
          ),
        ]
      } else {
        return [
          FunctionArgumentDescription(label: "message", expression: .identifierPattern("message")),
          metadata,
        ]
      }
    }

    return [
      CodeBlock(
        item: .declaration(
          .variable(
            kind: .let,
            left: .identifierPattern("request"),
            right: .functionCall(
              calledExpression: .identifierType(
                .clientRequest(forType: input, streaming: streamingInput)
              ),
              arguments: arguments(streaming: streamingInput)
            )
          )
        )
      ),
      CodeBlock(
        item: .expression(
          .return(
            .try(
              .await(
                .functionCall(
                  calledExpression: .identifierPattern("self").dot(name),
                  arguments: [
                    FunctionArgumentDescription(
                      label: "request",
                      expression: .identifierPattern("request")
                    ),
                    FunctionArgumentDescription(
                      label: "options",
                      expression: .identifierPattern("options")
                    ),
                    FunctionArgumentDescription(
                      label: "onResponse",
                      expression: .identifierPattern("handleResponse")
                    ),
                  ]
                )
              )
            )
          )
        )
      ),
    ]
  }
}

extension FunctionDescription {
  /// ```
  /// func foo<Result>(
  ///   _ message: <Input>,
  ///   metadata: GRPCCore.Metadata = [:],
  ///   options: GRPCCore.CallOptions = .defaults,
  ///   onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
  ///     try response.message
  ///   }
  /// ) async throws -> Result where Result: Sendable {
  ///   // ...
  /// }
  /// ```
  static func clientMethodExploded(
    accessLevel: AccessModifier? = nil,
    name: String,
    input: String,
    output: String,
    streamingInput: Bool,
    streamingOutput: Bool
  ) -> Self {
    FunctionDescription(
      signature: .clientMethodExploded(
        accessLevel: accessLevel,
        name: name,
        input: input,
        output: output,
        streamingInput: streamingInput,
        streamingOutput: streamingOutput
      ),
      body: .clientMethodExploded(name: name, input: input, streamingInput: streamingInput)
    )
  }
}

extension ExtensionDescription {
  /// ```
  /// extension <Name> {
  ///   // (exploded client methods)
  /// }
  /// ```
  static func explodedClientMethods(
    accessLevel: AccessModifier? = nil,
    on extensionName: String,
    methods: [MethodDescriptor]
  ) -> ExtensionDescription {
    return ExtensionDescription(
      onType: extensionName,
      declarations: methods.map { method in
        .commentable(
          .preFormatted(explodedDocs(for: method)),
          .function(
            .clientMethodExploded(
              accessLevel: accessLevel,
              name: method.name.functionName,
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

extension FunctionDescription {
  /// ```
  /// func <Name><Result>(
  ///   request: GRPCCore.ClientRequest<Input>,
  ///   serializer: some GRPCCore.MessageSerializer<Input>,
  ///   deserializer: some GRPCCore.MessageDeserializer<Output>,
  ///   options: GRPCCore.CallOptions = .default,
  ///   onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result
  /// ) async throws -> Result where Result: Sendable {
  ///   try await self.<Name>(...)
  /// }
  /// ```
  static func clientMethod(
    accessLevel: AccessModifier,
    name: String,
    input: String,
    output: String,
    serviceEnum: String,
    methodEnum: String,
    streamingInput: Bool,
    streamingOutput: Bool
  ) -> Self {
    let underlyingMethod: String
    switch (streamingInput, streamingOutput) {
    case (false, false):
      underlyingMethod = "unary"
    case (true, false):
      underlyingMethod = "clientStreaming"
    case (false, true):
      underlyingMethod = "serverStreaming"
    case (true, true):
      underlyingMethod = "bidirectionalStreaming"
    }

    return FunctionDescription(
      accessModifier: accessLevel,
      kind: .function(name: name),
      generics: [.member("Result")],
      parameters: [
        ParameterDescription(
          label: "request",
          type: .clientRequest(forType: input, streaming: streamingInput)
        ),
        ParameterDescription(
          label: "serializer",
          // Be explicit: 'type' is optional and '.some' resolves to Optional.some by default.
          type: ExistingTypeDescription.some(.serializer(forType: input))
        ),
        ParameterDescription(
          label: "deserializer",
          // Be explicit: 'type' is optional and '.some' resolves to Optional.some by default.
          type: ExistingTypeDescription.some(.deserializer(forType: output))
        ),
        ParameterDescription(
          label: "options",
          type: .callOptions,
          defaultValue: .dot("defaults")
        ),
        ParameterDescription(
          label: "onResponse",
          name: "handleResponse",
          type: .closure(
            ClosureSignatureDescription(
              parameters: [
                ParameterDescription(
                  type: .clientResponse(forType: output, streaming: streamingOutput)
                )
              ],
              keywords: [.async, .throws],
              returnType: .identifierPattern("Result"),
              sendable: true,
              escaping: true
            )
          ),
          defaultValue: streamingOutput
            ? nil
            : .closureInvocation(.defaultClientUnaryResponseHandler)
        ),
      ],
      keywords: [.async, .throws],
      returnType: .identifierPattern("Result"),
      whereClause: WhereClause(requirements: [.conformance("Result", "Sendable")]),
      body: [
        .try(
          .await(
            .functionCall(
              calledExpression: .identifierPattern("self").dot("client").dot(underlyingMethod),
              arguments: [
                FunctionArgumentDescription(
                  label: "request",
                  expression: .identifierPattern("request")
                ),
                FunctionArgumentDescription(
                  label: "descriptor",
                  expression: .identifierPattern(serviceEnum)
                    .dot("Method")
                    .dot(methodEnum)
                    .dot("descriptor")
                ),
                FunctionArgumentDescription(
                  label: "serializer",
                  expression: .identifierPattern("serializer")
                ),
                FunctionArgumentDescription(
                  label: "deserializer",
                  expression: .identifierPattern("deserializer")
                ),
                FunctionArgumentDescription(
                  label: "options",
                  expression: .identifierPattern("options")
                ),
                FunctionArgumentDescription(
                  label: "onResponse",
                  expression: .identifierPattern("handleResponse")
                ),
              ]
            )
          )
        )
      ]
    )
  }
}

extension StructDescription {
  /// ```
  /// struct <Name><Transport>: <ClientProtocol> where Transport: GRPCCore.ClientTransport {
  ///   private let client: GRPCCore.GRPCClient<Transport>
  ///
  ///   init(wrapping client: GRPCCore.GRPCClient<Transport>) {
  ///     self.client = client
  ///   }
  ///
  ///   // ...
  /// }
  /// ```
  static func client(
    accessLevel: AccessModifier,
    name: String,
    serviceEnum: String,
    clientProtocol: String,
    methods: [MethodDescriptor]
  ) -> Self {
    StructDescription(
      accessModifier: accessLevel,
      name: name,
      generics: [.member("Transport")],
      conformances: [clientProtocol],
      whereClause: WhereClause(
        requirements: [.conformance("Transport", "GRPCCore.ClientTransport")]
      ),
      members: [
        .variable(
          accessModifier: .private,
          kind: .let,
          left: "client",
          type: .grpcClient(genericOver: "Transport")
        ),
        .commentable(
          .preFormatted(
            """
            /// Creates a new client wrapping the provided `GRPCCore.GRPCClient`.
            ///
            /// - Parameters:
            ///   - client: A `GRPCCore.GRPCClient` providing a communication channel to the service.
            """
          ),
          .function(
            accessModifier: accessLevel,
            kind: .initializer,
            parameters: [
              ParameterDescription(
                label: "wrapping",
                name: "client",
                type: .grpcClient(
                  genericOver: "Transport"
                )
              )
            ],
            whereClause: nil,
            body: [
              .expression(
                .assignment(
                  left: .identifierPattern("self").dot("client"),
                  right: .identifierPattern("client")
                )
              )
            ]
          )
        ),
      ]
        + methods.map { method in
          .commentable(
            .preFormatted(docs(for: method)),
            .function(
              .clientMethod(
                accessLevel: accessLevel,
                name: method.name.functionName,
                input: method.inputType,
                output: method.outputType,
                serviceEnum: serviceEnum,
                methodEnum: method.name.typeName,
                streamingInput: method.isInputStreaming,
                streamingOutput: method.isOutputStreaming
              )
            )
          )
        }
    )
  }
}

private func docs(
  for method: MethodDescriptor,
  serializers includeSerializers: Bool = true
) -> String {
  let summary = "/// Call the \"\(method.name.identifyingName)\" method."

  let request: String
  if method.isInputStreaming {
    request = "A streaming request producing `\(method.inputType)` messages."
  } else {
    request = "A request containing a single `\(method.inputType)` message."
  }

  let parameters = """
    /// - Parameters:
    ///   - request: \(request)
    """

  let serializers = """
    ///   - serializer: A serializer for `\(method.inputType)` messages.
    ///   - deserializer: A deserializer for `\(method.outputType)` messages.
    """

  let otherParameters = """
    ///   - options: Options to apply to this RPC.
    ///   - handleResponse: A closure which handles the response, the result of which is
    ///       returned to the caller. Returning from the closure will cancel the RPC if it
    ///       hasn't already finished.
    /// - Returns: The result of `handleResponse`.
    """

  let allParameters: String
  if includeSerializers {
    allParameters = parameters + "\n" + serializers + "\n" + otherParameters
  } else {
    allParameters = parameters + "\n" + otherParameters
  }

  return Docs.interposeDocs(method.documentation, between: summary, and: allParameters)
}

private func explodedDocs(for method: MethodDescriptor) -> String {
  let summary = "/// Call the \"\(method.name.identifyingName)\" method."
  var parameters = """
    /// - Parameters:
    """

  if !method.isInputStreaming {
    parameters += "\n"
    parameters += """
      ///   - message: request message to send.
      """
  }

  parameters += "\n"
  parameters += """
    ///   - metadata: Additional metadata to send, defaults to empty.
    ///   - options: Options to apply to this RPC, defaults to `.defaults`.
    """

  if method.isInputStreaming {
    parameters += "\n"
    parameters += """
      ///   - producer: A closure producing request messages to send to the server. The request
      ///       stream is closed when the closure returns.
      """
  }

  parameters += "\n"
  parameters += """
    ///   - handleResponse: A closure which handles the response, the result of which is
    ///       returned to the caller. Returning from the closure will cancel the RPC if it
    ///       hasn't already finished.
    /// - Returns: The result of `handleResponse`.
    """

  return Docs.interposeDocs(method.documentation, between: summary, and: parameters)
}
