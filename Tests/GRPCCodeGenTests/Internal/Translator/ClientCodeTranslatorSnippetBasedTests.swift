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
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodA.descriptor,
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
      name: "methodA",
      isInputStreaming: true,
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
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodA.descriptor,
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
      isInputStreaming: false,
      isOutputStreaming: true,
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
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodA.descriptor,
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
      isInputStreaming: true,
      isOutputStreaming: true,
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
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.bidirectionalStreaming(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodA.descriptor,
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
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodB",
      name: "methodB",
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "namespaceA",
      methods: [methodA, methodB]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
          /// Documentation for MethodB
          func methodB<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodB.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodB.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodB.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension namespaceA.ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodA.Output>(),
                  body
              )
          }
          func methodB<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodB.Input>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodB(
                  request: request,
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.methodB.Input>(),
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.methodB.Output>(),
                  body
              )
          }
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
          let client: GRPCCore.GRPCClient
          init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<namespaceA.ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<namespaceA.ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  handler: body
              )
          }
          /// Documentation for MethodB
          func methodB<R>(
              request: ClientRequest.Single<namespaceA.ServiceA.Methods.methodB.Input>,
              serializer: some MessageSerializer<namespaceA.ServiceA.Methods.methodB.Input>,
              deserializer: some MessageDeserializer<namespaceA.ServiceA.Methods.methodB.Output>,
              _ body: @Sendable @escaping (ClientResponse.Stream<namespaceA.ServiceA.Methods.methodB.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: namespaceA.ServiceA.Methods.methodB.descriptor,
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
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "ServiceARequest",
      outputType: "ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      extension ServiceA.ClientProtocol {
          func methodA<R>(
              request: ClientRequest.Single<ServiceA.Methods.methodA.Input>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<ServiceA.Methods.methodA.Input>(),
                  deserializer: ProtobufDeserializer<ServiceA.Methods.methodA.Output>(),
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
              request: ClientRequest.Single<ServiceA.Methods.methodA.Input>,
              serializer: some MessageSerializer<ServiceA.Methods.methodA.Input>,
              deserializer: some MessageDeserializer<ServiceA.Methods.methodA.Output>,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceA.Methods.methodA.Output>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: ServiceA.Methods.methodA.descriptor,
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
      namespace: "namespaceA",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for ServiceB",
      name: "ServiceB",
      namespace: "",
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      protocol namespaceA_ServiceAClientProtocol: Sendable {}
      extension namespaceA.ServiceA.ClientProtocol {
      }
      /// Documentation for ServiceA
      struct namespaceA_ServiceAClient: namespaceA.ServiceA.ClientProtocol {
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
