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

import Testing

@testable import GRPCCodeGen

@Suite
final class ServerCodeTranslatorSnippetBasedTests {
  @Test
  func translate() {
    let method = MethodDescriptor(
      documentation: "/// Documentation for unaryMethod",
      name: Name(base: "UnaryMethod", generatedUpperCase: "Unary", generatedLowerCase: "unary"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )

    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(
        base: "AlongNameForServiceA",
        generatedUpperCase: "ServiceA",
        generatedLowerCase: "serviceA"
      ),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: [method]
    )

    let expectedSwift = """
      extension NamespaceA_ServiceA {
          /// Streaming variant of the service protocol for the "namespaceA.AlongNameForServiceA" service.
          ///
          /// This protocol is the lowest-level of the service protocols generated for this service
          /// giving you the most flexibility over the implementation of your service. This comes at
          /// the cost of more verbose and less strict APIs. Each RPC requires you to implement it in
          /// terms of a request stream and response stream. Where only a single request or response
          /// message is expected, you are responsible for enforcing this invariant is maintained.
          ///
          /// Where possible, prefer using the stricter, less-verbose ``ServiceProtocol``
          /// or ``SimpleServiceProtocol`` instead.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for ServiceA
          public protocol StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
              /// Handle the "UnaryMethod" method.
              ///
              /// > Source IDL Documentation:
              /// >
              /// > Documentation for unaryMethod
              ///
              /// - Parameters:
              ///   - request: A streaming request of `NamespaceA_ServiceARequest` messages.
              ///   - context: Context providing information about the RPC.
              /// - Throws: Any error which occurred during the processing of the request. Thrown errors
              ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
              ///     to an internal error.
              /// - Returns: A streaming response of `NamespaceA_ServiceAResponse` messages.
              func unary(
                  request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
                  context: GRPCCore.ServerContext
              ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
          }

          /// Service protocol for the "namespaceA.AlongNameForServiceA" service.
          ///
          /// This protocol is higher level than ``StreamingServiceProtocol`` but lower level than
          /// the ``SimpleServiceProtocol``, it provides access to request and response metadata and
          /// trailing response metadata. If you don't need these then consider using
          /// the ``SimpleServiceProtocol``. If you need fine grained control over your RPCs then
          /// use ``StreamingServiceProtocol``.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for ServiceA
          public protocol ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {
              /// Handle the "UnaryMethod" method.
              ///
              /// > Source IDL Documentation:
              /// >
              /// > Documentation for unaryMethod
              ///
              /// - Parameters:
              ///   - request: A request containing a single `NamespaceA_ServiceARequest` message.
              ///   - context: Context providing information about the RPC.
              /// - Throws: Any error which occurred during the processing of the request. Thrown errors
              ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
              ///     to an internal error.
              /// - Returns: A response containing a single `NamespaceA_ServiceAResponse` message.
              func unary(
                  request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
                  context: GRPCCore.ServerContext
              ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>
          }

          /// Simple service protocol for the "namespaceA.AlongNameForServiceA" service.
          ///
          /// This is the highest level protocol for the service. The API is the easiest to use but
          /// doesn't provide access to request or response metadata. If you need access to these
          /// then use ``ServiceProtocol`` instead.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for ServiceA
          public protocol SimpleServiceProtocol: NamespaceA_ServiceA.ServiceProtocol {
              /// Handle the "UnaryMethod" method.
              ///
              /// > Source IDL Documentation:
              /// >
              /// > Documentation for unaryMethod
              ///
              /// - Parameters:
              ///   - request: A `NamespaceA_ServiceARequest` message.
              ///   - context: Context providing information about the RPC.
              /// - Throws: Any error which occurred during the processing of the request. Thrown errors
              ///     of type `RPCError` are mapped to appropriate statuses. All other errors are converted
              ///     to an internal error.
              /// - Returns: A `NamespaceA_ServiceAResponse` to respond with.
              func unary(
                  request: NamespaceA_ServiceARequest,
                  context: GRPCCore.ServerContext
              ) async throws -> NamespaceA_ServiceAResponse
          }
      }
      // Default implementation of 'registerMethods(with:)'.
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA_ServiceA.Method.Unary.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.unary(
                          request: request,
                          context: context
                      )
                  }
              )
          }
      }
      // Default implementation of streaming methods from 'StreamingServiceProtocol'.
      extension NamespaceA_ServiceA.ServiceProtocol {
          public func unary(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.unary(
                  request: GRPCCore.ServerRequest(stream: request),
                  context: context
              )
              return GRPCCore.StreamingServerResponse(single: response)
          }
      }
      // Default implementation of methods from 'ServiceProtocol'.
      extension NamespaceA_ServiceA.SimpleServiceProtocol {
          public func unary(
              request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse> {
              return GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>(
                  message: try await self.unary(
                      request: request.message,
                      context: context
                  ),
                  metadata: [:]
              )
          }
      }
      """

    let rendered = self.render(accessLevel: .public, service: service)
    #expect(rendered == expectedSwift)
  }

  private func render(
    accessLevel: AccessModifier,
    service: ServiceDescriptor
  ) -> String {
    let translator = ServerCodeTranslator()
    let codeBlocks = translator.translate(accessModifier: accessLevel, service: service) {
      "GRPCProtobuf.ProtobufSerializer<\($0)>()"
    } deserializer: {
      "GRPCProtobuf.ProtobufDeserializer<\($0)>()"
    }
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    return renderer.renderedContents()
  }
}
