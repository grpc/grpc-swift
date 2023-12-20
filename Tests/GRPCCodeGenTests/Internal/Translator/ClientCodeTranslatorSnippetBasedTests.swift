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

import XCTest

@testable import GRPCCodeGen

final class ClientCodeTranslatorSnippetBasedTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testClientCodeTranslator() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "methodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "namespaceA",
      methods: [method]
    )
    let expectedSwift =
      """
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          func methodA<R: Sendable>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async rethrows -> R
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R: Sendable>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async rethrows -> R {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
      }
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          func methodA<R: Sendable>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) {
              try await self.client.unary(
                  request,
                  namespaceA.ServiceA.Methods.methodA.descriptor,
                  serializer,
                  deserializer,
                  body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  private func makeCodeGenerationRequest(services: [ServiceDescriptor]) -> CodeGenerationRequest {
    return CodeGenerationRequest(
      fileName: "test.grpc",
      leadingTrivia: "Some really exciting license header 2023.",
      dependencies: [],
      services: services,
      lookupSerializer: {
        "ProtobufSerializer<\($0)>()"
      },
      lookupDeserializer: {
        "ProtobufDeserializer<\($0)>()"
      }
    )
  }

  private func assertClientCodeTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = ClientCodeTranslator()
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}
