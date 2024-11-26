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
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for unaryMethod
          func unary(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {
          /// Documentation for unaryMethod
          func unary(
              request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
      """

    let rendered = self.render(accessLevel: .public, service: service)
    #expect(rendered == expectedSwift)
  }

  private func render(
    accessLevel: AccessModifier,
    service: ServiceDescriptor
  ) -> String {
    let translator = ServerCodeTranslator()
    let codeBlocks = translator.translate(accessModifier: accessLevel, services: [service]) {
      "GRPCProtobuf.ProtobufSerializer<\($0)>()"
    } deserializer: {
      "GRPCProtobuf.ProtobufDeserializer<\($0)>()"
    }

    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    return renderer.renderedContents()
  }
}
