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

#if os(macOS) || os(Linux)  // swift-format doesn't like canImport(Foundation.Process)

import XCTest

@testable import GRPCCodeGen

final class ClientCodeTranslatorSnippetBasedTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testClientCodeTranslatorUnaryMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "MethodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension NamespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorClientStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "MethodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension NamespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorServerStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "methodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension NamespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorBidirectionalStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "methodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: true,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension NamespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.bidirectionalStreaming(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorMultipleMethods() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "methodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodB",
      name: "methodB",
      generatedName: "MethodB",
      signatureName: "methodB",
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: [methodA, methodB]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
          /// Documentation for MethodB
          func methodB<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodB.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodB.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodB.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension NamespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
          func methodB<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodB.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodB(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Methods.MethodB.Input>(),
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Methods.MethodB.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA.ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA.ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
          /// Documentation for MethodB
          func methodB<R>(
              request: ClientRequest.Single<NamespaceA.ServiceA.Methods.MethodB.Input>,
              serializer: some MessageSerializer<NamespaceA.ServiceA.Methods.MethodB.Input>,
              deserializer: some MessageDeserializer<NamespaceA.ServiceA.Methods.MethodB.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA.ServiceA.Methods.MethodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA.ServiceA.Methods.MethodB.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorNoNamespaceService() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "methodA",
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "ServiceARequest",
      outputType: "ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "",
      generatedNamespace: "",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<ServiceA.Methods.MethodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<ServiceA.Methods.MethodA.Input>(),
                  deserializer: ProtobufDeserializer<ServiceA.Methods.MethodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct ServiceAClient: ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<ServiceA.Methods.MethodA.Input>,
              serializer: some MessageSerializer<ServiceA.Methods.MethodA.Input>,
              deserializer: some MessageDeserializer<ServiceA.Methods.MethodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.MethodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: ServiceA.Methods.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testClientCodeTranslatorMultipleServices() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for ServiceB",
      name: "ServiceB",
      generatedName: "ServiceB",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol NamespaceA_ServiceAClientProtocol: Sendable {}
      extension NamespaceA.ServiceA.ClientProtocol {
      }
      /// Documentation for ServiceA
      struct NamespaceA_ServiceAClient: NamespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      /// Documentation for ServiceB
      protocol ServiceBClientProtocol: Sendable {}
      extension ServiceB.ClientProtocol {
      }
      /// Documentation for ServiceB
      struct ServiceBClient: ServiceB.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift
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

#endif  // os(macOS) || os(Linux)
