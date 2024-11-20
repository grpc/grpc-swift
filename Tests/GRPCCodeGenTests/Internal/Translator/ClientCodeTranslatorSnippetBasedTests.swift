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
struct ClientCodeTranslatorSnippetBasedTests {
  @Test
  func translate() {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )

    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )

    let expectedSwift = """
      extension NamespaceA_ServiceA {
          /// Documentation for ServiceA
          public protocol ClientProtocol: Sendable {
              /// Documentation for MethodA
              func methodA<Result>(
                  request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
                  serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
                  deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
                  options: GRPCCore.CallOptions,
                  onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result
              ) async throws -> Result where Result: Sendable
          }

          /// Documentation for ServiceA
          public struct Client: ClientProtocol {
              private let client: GRPCCore.GRPCClient

              public init(wrapping client: GRPCCore.GRPCClient) {
                  self.client = client
              }

              /// Documentation for MethodA
              public func methodA<Result>(
                  request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
                  serializer: some GRPCCore.MessageSerializer<NamespaceA_ServiceARequest>,
                  deserializer: some GRPCCore.MessageDeserializer<NamespaceA_ServiceAResponse>,
                  options: GRPCCore.CallOptions = .defaults,
                  onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                      try response.message
                  }
              ) async throws -> Result where Result: Sendable {
                  try await self.client.unary(
                      request: request,
                      descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                      serializer: serializer,
                      deserializer: deserializer,
                      options: options,
                      onResponse: handleResponse
                  )
              }
          }
      }
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<Result>(
              request: GRPCCore.ClientRequest<NamespaceA_ServiceARequest>,
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                  try response.message
              }
          ) async throws -> Result where Result: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  onResponse: handleResponse
              )
          }
      }
      extension NamespaceA_ServiceA.ClientProtocol {
          /// Documentation for MethodA
          public func methodA<Result>(
              _ message: NamespaceA_ServiceARequest,
              metadata: GRPCCore.Metadata = [:],
              options: GRPCCore.CallOptions = .defaults,
              onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<NamespaceA_ServiceAResponse>) async throws -> Result = { response in
                  try response.message
              }
          ) async throws -> Result where Result: Sendable {
              let request = GRPCCore.ClientRequest<NamespaceA_ServiceARequest>(
                  message: message,
                  metadata: metadata
              )
              return try await self.methodA(
                  request: request,
                  options: options,
                  onResponse: handleResponse
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
    let translator = ClientCodeTranslator()
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
