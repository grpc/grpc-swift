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
  @Suite("Server")
  struct Server {
    @Test(
      "func <Method>(request:context:) async throws -> ...",
      arguments: AccessModifier.allCases,
      RPCKind.allCases
    )
    func serverMethodSignature(access: AccessModifier, kind: RPCKind) {
      let decl: FunctionSignatureDescription = .serverMethod(
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
          \(access) func foo(
            request: GRPCCore.ServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<Output>
          """
      case .clientStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<Output>
          """
      case .serverStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.ServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output>
          """
      case .bidirectionalStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output>
          """
      }

      #expect(render(.function(signature: decl)) == expected)
    }

    @Test("protocol StreamingServiceProtocol { ... }", arguments: AccessModifier.allCases)
    func serverStreamingServiceProtocol(access: AccessModifier) {
      let decl: ProtocolDescription = .streamingService(
        accessLevel: access,
        name: "FooService",
        methods: [
          .init(
            documentation: "/// Some docs",
            name: .init(base: "Foo", generatedUpperCase: "Foo", generatedLowerCase: "foo"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "FooInput",
            outputType: "FooOutput"
          )
        ]
      )

      let expected = """
        \(access) protocol FooService: GRPCCore.RegistrableRPCService {
          /// Handle the "Foo" method.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Some docs
          ///
          /// - Parameters:
          ///   - request: A streaming request of `FooInput` messages.
          ///   - context: Context providing information about the RPC.
          /// - Throws: Any error which occurred during the processing of the request. Thrown errors
          ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
          ///     to an internal error.
          /// - Returns: A streaming response of `FooOutput` messages.
          func foo(
            request: GRPCCore.StreamingServerRequest<FooInput>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<FooOutput>
        }
        """

      #expect(render(.protocol(decl)) == expected)
    }

    @Test("protocol ServiceProtocol { ... }", arguments: AccessModifier.allCases)
    func serverServiceProtocol(access: AccessModifier) {
      let decl: ProtocolDescription = .service(
        accessLevel: access,
        name: "FooService",
        streamingProtocol: "FooService_StreamingServiceProtocol",
        methods: [
          .init(
            documentation: "/// Some docs",
            name: .init(base: "Foo", generatedUpperCase: "Foo", generatedLowerCase: "foo"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "FooInput",
            outputType: "FooOutput"
          )
        ]
      )

      let expected = """
        \(access) protocol FooService: FooService_StreamingServiceProtocol {
          /// Handle the "Foo" method.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Some docs
          ///
          /// - Parameters:
          ///   - request: A request containing a single `FooInput` message.
          ///   - context: Context providing information about the RPC.
          /// - Throws: Any error which occurred during the processing of the request. Thrown errors
          ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
          ///     to an internal error.
          /// - Returns: A response containing a single `FooOutput` message.
          func foo(
            request: GRPCCore.ServerRequest<FooInput>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<FooOutput>
        }
        """

      #expect(render(.protocol(decl)) == expected)
    }

    @Test("{ router, context in try await self.<Method>(...) }")
    func routerHandlerInvokingRPC() {
      let expression: ClosureInvocationDescription = .routerHandlerInvokingRPC(method: "foo")
      let expected = """
        { request, context in
          try await self.foo(
            request: request,
            context: context
          )
        }
        """
      #expect(render(.closureInvocation(expression)) == expected)
    }

    @Test("router.registerHandler(...) { ... }")
    func registerMethodsWithRouter() {
      let expression: FunctionCallDescription = .registerWithRouter(
        serviceNamespace: "FooService",
        methodNamespace: "Bar",
        methodName: "bar",
        inputDeserializer: "Deserialize<BarInput>()",
        outputSerializer: "Serialize<BarOutput>()"
      )

      let expected = """
        router.registerHandler(
          forMethod: FooService.Method.Bar.descriptor,
          deserializer: Deserialize<BarInput>(),
          serializer: Serialize<BarOutput>(),
          handler: { request, context in
            try await self.bar(
              request: request,
              context: context
            )
          }
        )
        """

      #expect(render(.functionCall(expression)) == expected)
    }

    @Test("func registerMethods(router:)", arguments: AccessModifier.allCases)
    func registerMethods(access: AccessModifier) {
      let expression: FunctionDescription = .registerMethods(
        accessLevel: access,
        serviceNamespace: "FooService",
        methods: [
          .init(
            documentation: "",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "BarInput",
            outputType: "BarOutput"
          )
        ]
      ) { type in
        "Serialize<\(type)>()"
      } deserializer: { type in
        "Deserialize<\(type)>()"
      }

      let expected = """
        \(access) func registerMethods(with router: inout GRPCCore.RPCRouter) {
          router.registerHandler(
            forMethod: FooService.Method.Bar.descriptor,
            deserializer: Deserialize<BarInput>(),
            serializer: Serialize<BarOutput>(),
            handler: { request, context in
              try await self.bar(
                request: request,
                context: context
              )
            }
          )
        }
        """

      #expect(render(.function(expression)) == expected)
    }

    @Test(
      "func <Method>(request:context:) async throw { ... (convert to/from single) ... }",
      arguments: AccessModifier.allCases,
      RPCKind.allCases
    )
    func serverStreamingMethodsCallingMethod(access: AccessModifier, kind: RPCKind) {
      let expression: FunctionDescription = .serverStreamingMethodsCallingMethod(
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
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output> {
            let response = try await self.foo(
              request: GRPCCore.ServerRequest(stream: request),
              context: context
            )
            return GRPCCore.StreamingServerResponse(single: response)
          }
          """
      case .serverStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output> {
            let response = try await self.foo(
              request: GRPCCore.ServerRequest(stream: request),
              context: context
            )
            return response
          }
          """
      case .clientStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output> {
            let response = try await self.foo(
              request: request,
              context: context
            )
            return GRPCCore.StreamingServerResponse(single: response)
          }
          """
      case .bidirectionalStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<Input>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<Output> {
            let response = try await self.foo(
              request: request,
              context: context
            )
            return response
          }
          """
      }

      #expect(render(.function(expression)) == expected)
    }

    @Test("extension FooService_ServiceProtocol { ... }", arguments: AccessModifier.allCases)
    func streamingServiceProtocolDefaultImplementation(access: AccessModifier) {
      let decl: ExtensionDescription = .streamingServiceProtocolDefaultImplementation(
        accessModifier: access,
        on: "Foo_ServiceProtocol",
        methods: [
          .init(
            documentation: "",
            name: .init(base: "Foo", generatedUpperCase: "Foo", generatedLowerCase: "foo"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "FooInput",
            outputType: "FooOutput"
          ),
          // Will be ignored as a bidirectional streaming method.
          .init(
            documentation: "",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: true,
            isOutputStreaming: true,
            inputType: "BarInput",
            outputType: "BarOutput"
          ),
        ]
      )

      let expected = """
        extension Foo_ServiceProtocol {
          \(access) func foo(
            request: GRPCCore.StreamingServerRequest<FooInput>,
            context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<FooOutput> {
            let response = try await self.foo(
              request: GRPCCore.ServerRequest(stream: request),
              context: context
            )
            return GRPCCore.StreamingServerResponse(single: response)
          }
        }
        """

      #expect(render(.extension(decl)) == expected)
    }

    @Test(
      "func <Method>(request:response:context:) (simple)",
      arguments: AccessModifier.allCases,
      RPCKind.allCases
    )
    func simpleServerMethod(access: AccessModifier, kind: RPCKind) {
      let decl: FunctionSignatureDescription = .simpleServerMethod(
        accessLevel: access,
        name: "foo",
        input: "FooInput",
        output: "FooOutput",
        streamingInput: kind.streamsInput,
        streamingOutput: kind.streamsOutput
      )

      let expected: String
      switch kind {
      case .unary:
        expected = """
          \(access) func foo(
            request: FooInput,
            context: GRPCCore.ServerContext
          ) async throws -> FooOutput
          """

      case .clientStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.RPCAsyncSequence<FooInput, any Swift.Error>,
            context: GRPCCore.ServerContext
          ) async throws -> FooOutput
          """

      case .serverStreaming:
        expected = """
          \(access) func foo(
            request: FooInput,
            response: GRPCCore.RPCWriter<FooOutput>,
            context: GRPCCore.ServerContext
          ) async throws
          """

      case .bidirectionalStreaming:
        expected = """
          \(access) func foo(
            request: GRPCCore.RPCAsyncSequence<FooInput, any Swift.Error>,
            response: GRPCCore.RPCWriter<FooOutput>,
            context: GRPCCore.ServerContext
          ) async throws
          """
      }

      #expect(render(.function(signature: decl)) == expected)
    }

    @Test("protocol SimpleServiceProtocol { ... }", arguments: AccessModifier.allCases)
    func simpleServiceProtocol(access: AccessModifier) {
      let decl: ProtocolDescription = .simpleServiceProtocol(
        accessModifier: access,
        name: "SimpleServiceProtocol",
        serviceProtocol: "ServiceProtocol",
        methods: [
          .init(
            documentation: "",
            name: .init(base: "Foo", generatedUpperCase: "Foo", generatedLowerCase: "foo"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "Input",
            outputType: "Output"
          )
        ]
      )

      let expected = """
        \(access) protocol SimpleServiceProtocol: ServiceProtocol {
          /// Handle the "Foo" method.
          ///
          /// - Parameters:
          ///   - request: A `Input` message.
          ///   - context: Context providing information about the RPC.
          /// - Throws: Any error which occurred during the processing of the request. Thrown errors
          ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
          ///     to an internal error.
          /// - Returns: A `Output` to respond with.
          func foo(
            request: Input,
            context: GRPCCore.ServerContext
          ) async throws -> Output
        }
        """

      #expect(render(.protocol(decl)) == expected)
    }
  }
}
