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

import Testing

@testable import GRPCCodeGen

extension StructuedSwiftTests {
  @Suite("Client")
  struct Client {
    @Test(
      "func <Method>(request:serializer:deserializer:options:onResponse:)",
      arguments: AccessModifier.allCases,
      RPCKind.allCases
    )
    func clientMethodSignature(access: AccessModifier, kind: RPCKind) {
      let decl: FunctionSignatureDescription = .clientMethod(
        accessLevel: access,
        name: "foo",
        input: "FooInput",
        output: "FooOutput",
        streamingInput: kind.streamsInput,
        streamingOutput: kind.streamsOutput,
        includeDefaults: false,
        includeSerializers: true
      )

      let requestType = kind.streamsInput ? "StreamingClientRequest" : "ClientRequest"
      let responseType = kind.streamsOutput ? "StreamingClientResponse" : "ClientResponse"

      let expected = """
        \(access) func foo<Result>(
          request: GRPCCore.\(requestType)<FooInput>,
          serializer: some GRPCCore.MessageSerializer<FooInput>,
          deserializer: some GRPCCore.MessageDeserializer<FooOutput>,
          options: GRPCCore.CallOptions,
          onResponse handleResponse: @Sendable @escaping (GRPCCore.\(responseType)<FooOutput>) async throws -> Result
        ) async throws -> Result where Result: Sendable
        """

      #expect(render(.function(signature: decl)) == expected)
    }

    @Test(
      "func <Method>(request:serializer:deserializer:options:onResponse:) (with defaults)",
      arguments: AccessModifier.allCases,
      [true, false]
    )
    func clientMethodSignatureWithDefaults(access: AccessModifier, streamsOutput: Bool) {
      let decl: FunctionSignatureDescription = .clientMethod(
        accessLevel: access,
        name: "foo",
        input: "FooInput",
        output: "FooOutput",
        streamingInput: false,
        streamingOutput: streamsOutput,
        includeDefaults: true,
        includeSerializers: false
      )

      let expected: String
      if streamsOutput {
        expected = """
          \(access) func foo<Result>(
            request: GRPCCore.ClientRequest<FooInput>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<FooOutput>) async throws -> Result
          ) async throws -> Result where Result: Sendable
          """
      } else {
        expected = """
          \(access) func foo<Result>(
            request: GRPCCore.ClientRequest<FooInput>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<FooOutput>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable
          """
      }

      #expect(render(.function(signature: decl)) == expected)
    }

    @Test("protocol Foo_ClientProtocol: Sendable { ... }", arguments: AccessModifier.allCases)
    func clientProtocol(access: AccessModifier) {
      let decl: ProtocolDescription = .clientProtocol(
        accessLevel: access,
        name: "Foo_ClientProtocol",
        methods: [
          .init(
            documentation: "/// Some docs",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "BarInput",
            outputType: "BarOutput"
          )
        ]
      )

      let expected = """
        \(access) protocol Foo_ClientProtocol: Sendable {
          /// Some docs
          func bar<Result>(
            request: GRPCCore.ClientRequest<BarInput>,
            serializer: some GRPCCore.MessageSerializer<BarInput>,
            deserializer: some GRPCCore.MessageDeserializer<BarOutput>,
            options: GRPCCore.CallOptions,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<BarOutput>) async throws -> Result
          ) async throws -> Result where Result: Sendable
        }
        """

      #expect(render(.protocol(decl)) == expected)
    }

    @Test("func foo(...) { try await self.foo(...) }", arguments: AccessModifier.allCases)
    func clientMethodFunctionWithDefaults(access: AccessModifier) {
      let decl: FunctionDescription = .clientMethodWithDefaults(
        accessLevel: access,
        name: "foo",
        input: "FooInput",
        output: "FooOutput",
        streamingInput: false,
        streamingOutput: false,
        serializer: .identifierPattern("Serialize<FooInput>()"),
        deserializer: .identifierPattern("Deserialize<FooOutput>()")
      )

      let expected = """
        \(access) func foo<Result>(
          request: GRPCCore.ClientRequest<FooInput>,
          options: GRPCCore.CallOptions = .defaults,
          onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<FooOutput>) async throws -> Result = { response in
            try response.message
          }
        ) async throws -> Result where Result: Sendable {
          try await self.foo(
            request: request,
            serializer: Serialize<FooInput>(),
            deserializer: Deserialize<FooOutput>(),
            options: options,
            onResponse: handleResponse
          )
        }
        """

      #expect(render(.function(decl)) == expected)
    }

    @Test(
      "extension Foo_ClientProtocol { ... } (methods with defaults)",
      arguments: AccessModifier.allCases
    )
    func extensionWithDefaultClientMethods(access: AccessModifier) {
      let decl: ExtensionDescription = .clientMethodSignatureWithDefaults(
        accessLevel: access,
        name: "Foo_ClientProtocol",
        methods: [
          MethodDescriptor(
            documentation: "",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "BarInput",
            outputType: "BarOutput"
          )
        ],
        serializer: { "Serialize<\($0)>()" },
        deserializer: { "Deserialize<\($0)>()" }
      )

      let expected = """
        extension Foo_ClientProtocol {
          \(access) func bar<Result>(
            request: GRPCCore.ClientRequest<BarInput>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<BarOutput>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable {
            try await self.bar(
              request: request,
              serializer: Serialize<BarInput>(),
              deserializer: Deserialize<BarOutput>(),
              options: options,
              onResponse: handleResponse
            )
          }
        }
        """

      #expect(render(.extension(decl)) == expected)
    }

    @Test(
      "func foo<Result>(_:metadata:options:onResponse:) -> Result (exploded signature)",
      arguments: AccessModifier.allCases,
      RPCKind.allCases
    )
    func explodedClientMethodSignature(access: AccessModifier, kind: RPCKind) {
      let decl: FunctionSignatureDescription = .clientMethodExploded(
        accessLevel: access,
        name: "foo",
        input: "Input",
        output: "Output",
        streamingInput: kind.streamsInput,
        streamingOutput: kind.streamsOutput
      )

      let expected: String
      switch kind {
      case .unary:
        expected = """
          \(access) func foo<Result>(
            _ message: Input,
            metadata: GRPCCore.Metadata = [:],
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable
          """
      case .clientStreaming:
        expected = """
          \(access) func foo<Result>(
            metadata: GRPCCore.Metadata = [:],
            options: GRPCCore.CallOptions = .defaults,
            requestProducer producer: @Sendable @escaping (GRPCCore.RPCWriter<Input>) async throws -> Void,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable
          """
      case .serverStreaming:
        expected = """
          \(access) func foo<Result>(
            _ message: Input,
            metadata: GRPCCore.Metadata = [:],
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Output>) async throws -> Result
          ) async throws -> Result where Result: Sendable
          """
      case .bidirectionalStreaming:
        expected = """
          \(access) func foo<Result>(
            metadata: GRPCCore.Metadata = [:],
            options: GRPCCore.CallOptions = .defaults,
            requestProducer producer: @Sendable @escaping (GRPCCore.RPCWriter<Input>) async throws -> Void,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Output>) async throws -> Result
          ) async throws -> Result where Result: Sendable
          """
      }

      #expect(render(.function(signature: decl)) == expected)
    }

    @Test(
      "func foo<Result>(_:metadata:options:onResponse:) -> Result (exploded body)",
      arguments: [true, false]
    )
    func explodedClientMethodBody(streamingInput: Bool) {
      let blocks: [CodeBlock] = .clientMethodExploded(
        name: "foo",
        input: "Input",
        streamingInput: streamingInput
      )

      let expected: String
      if streamingInput {
        expected = """
          let request = GRPCCore.StreamingClientRequest<Input>(
            metadata: metadata,
            producer: producer
          )
          return try await self.foo(
            request: request,
            options: options,
            onResponse: handleResponse
          )
          """

      } else {
        expected = """
          let request = GRPCCore.ClientRequest<Input>(
            message: message,
            metadata: metadata
          )
          return try await self.foo(
            request: request,
            options: options,
            onResponse: handleResponse
          )
          """
      }

      #expect(render(blocks) == expected)
    }

    @Test("extension Foo_ClientProtocol { ... } (exploded)", arguments: AccessModifier.allCases)
    func explodedClientMethodExtension(access: AccessModifier) {
      let decl: ExtensionDescription = .explodedClientMethods(
        accessLevel: access,
        on: "Foo_ClientProtocol",
        methods: [
          .init(
            documentation: "/// Some docs",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: false,
            isOutputStreaming: true,
            inputType: "Input",
            outputType: "Output"
          )
        ]
      )

      let expected = """
        extension Foo_ClientProtocol {
          /// Some docs
          \(access) func bar<Result>(
            _ message: Input,
            metadata: GRPCCore.Metadata = [:],
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Output>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
            let request = GRPCCore.ClientRequest<Input>(
              message: message,
              metadata: metadata
            )
            return try await self.bar(
              request: request,
              options: options,
              onResponse: handleResponse
            )
          }
        }
        """

      #expect(render(.extension(decl)) == expected)
    }

    @Test(
      "func foo(request:serializer:deserializer:options:onResponse:) (client method impl.)",
      arguments: AccessModifier.allCases
    )
    func clientMethodImplementation(access: AccessModifier) {
      let decl: FunctionDescription = .clientMethod(
        accessLevel: access,
        name: "foo",
        input: "Input",
        output: "Output",
        serviceEnum: "BarService",
        methodEnum: "Foo",
        streamingInput: false,
        streamingOutput: false
      )

      let expected = """
        \(access) func foo<Result>(
          request: GRPCCore.ClientRequest<Input>,
          serializer: some GRPCCore.MessageSerializer<Input>,
          deserializer: some GRPCCore.MessageDeserializer<Output>,
          options: GRPCCore.CallOptions = .defaults,
          onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
            try response.message
          }
        ) async throws -> Result where Result: Sendable {
          try await self.client.unary(
            request: request,
            descriptor: BarService.Method.Foo.descriptor,
            serializer: serializer,
            deserializer: deserializer,
            options: options,
            onResponse: handleResponse
          )
        }
        """

      #expect(render(.function(decl)) == expected)
    }

    @Test("struct FooClient: Foo_ClientProtocol { ... }", arguments: AccessModifier.allCases)
    func client(access: AccessModifier) {
      let decl: StructDescription = .client(
        accessLevel: access,
        name: "FooClient",
        serviceEnum: "BarService",
        clientProtocol: "Foo_ClientProtocol",
        methods: [
          .init(
            documentation: "/// Unary docs",
            name: .init(
              base: "Unary",
              generatedUpperCase: "Unary",
              generatedLowerCase: "unary"
            ),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "Input",
            outputType: "Output"
          ),
          .init(
            documentation: "/// ClientStreaming docs",
            name: .init(
              base: "ClientStreaming",
              generatedUpperCase: "ClientStreaming",
              generatedLowerCase: "clientStreaming"
            ),
            isInputStreaming: true,
            isOutputStreaming: false,
            inputType: "Input",
            outputType: "Output"
          ),
          .init(
            documentation: "/// ServerStreaming docs",
            name: .init(
              base: "ServerStreaming",
              generatedUpperCase: "ServerStreaming",
              generatedLowerCase: "serverStreaming"
            ),
            isInputStreaming: false,
            isOutputStreaming: true,
            inputType: "Input",
            outputType: "Output"
          ),
          .init(
            documentation: "/// BidiStreaming docs",
            name: .init(
              base: "BidiStreaming",
              generatedUpperCase: "BidiStreaming",
              generatedLowerCase: "bidiStreaming"
            ),
            isInputStreaming: true,
            isOutputStreaming: true,
            inputType: "Input",
            outputType: "Output"
          ),
        ]
      )

      let expected = """
        \(access) struct FooClient: Foo_ClientProtocol {
          private let client: GRPCCore.GRPCClient

          \(access) init(wrapping client: GRPCCore.GRPCClient) {
            self.client = client
          }

          /// Unary docs
          \(access) func unary<Result>(
            request: GRPCCore.ClientRequest<Input>,
            serializer: some GRPCCore.MessageSerializer<Input>,
            deserializer: some GRPCCore.MessageDeserializer<Output>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable {
            try await self.client.unary(
              request: request,
              descriptor: BarService.Method.Unary.descriptor,
              serializer: serializer,
              deserializer: deserializer,
              options: options,
              onResponse: handleResponse
            )
          }

          /// ClientStreaming docs
          \(access) func clientStreaming<Result>(
            request: GRPCCore.StreamingClientRequest<Input>,
            serializer: some GRPCCore.MessageSerializer<Input>,
            deserializer: some GRPCCore.MessageDeserializer<Output>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<Output>) async throws -> Result = { response in
              try response.message
            }
          ) async throws -> Result where Result: Sendable {
            try await self.client.clientStreaming(
              request: request,
              descriptor: BarService.Method.ClientStreaming.descriptor,
              serializer: serializer,
              deserializer: deserializer,
              options: options,
              onResponse: handleResponse
            )
          }

          /// ServerStreaming docs
          \(access) func serverStreaming<Result>(
            request: GRPCCore.ClientRequest<Input>,
            serializer: some GRPCCore.MessageSerializer<Input>,
            deserializer: some GRPCCore.MessageDeserializer<Output>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Output>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
            try await self.client.serverStreaming(
              request: request,
              descriptor: BarService.Method.ServerStreaming.descriptor,
              serializer: serializer,
              deserializer: deserializer,
              options: options,
              onResponse: handleResponse
            )
          }

          /// BidiStreaming docs
          \(access) func bidiStreaming<Result>(
            request: GRPCCore.StreamingClientRequest<Input>,
            serializer: some GRPCCore.MessageSerializer<Input>,
            deserializer: some GRPCCore.MessageDeserializer<Output>,
            options: GRPCCore.CallOptions = .defaults,
            onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<Output>) async throws -> Result
          ) async throws -> Result where Result: Sendable {
            try await self.client.bidirectionalStreaming(
              request: request,
              descriptor: BarService.Method.BidiStreaming.descriptor,
              serializer: serializer,
              deserializer: deserializer,
              options: options,
              onResponse: handleResponse
            )
          }
        }
        """

      #expect(render(.struct(decl)) == expected)
    }
  }
}
