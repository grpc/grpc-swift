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
  typealias Name = GRPCCodeGen.CodeGenerationRequest.Name

  func testClientCodeTranslatorUnaryMethod() throws {
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
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorClientStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
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
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorServerStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorBidirectionalStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          public func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          public func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.bidirectionalStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testClientCodeTranslatorMultipleMethod() throws {
    let methodA = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "/// Documentation for MethodB",
      name: Name(base: "MethodB", generatedUpperCase: "MethodB", generatedLowerCase: "methodB"),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "namespaceA", generatedUpperCase: "NamespaceA", generatedLowerCase: ""),
      methods: [methodA, methodB]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
          
          /// Documentation for MethodB
          func methodB<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
          package func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
          
          package func methodB<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.methodB(
                  request: request,
                  serializer: ProtobufSerializer<NamespaceA_ServiceARequest>(),
                  deserializer: ProtobufDeserializer<NamespaceA_ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          package init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          package func methodA<R>(
              request: ClientRequest.Stream<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<NamespaceA_ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.clientStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
          
          /// Documentation for MethodB
          package func methodB<R>(
              request: ClientRequest.Single<NamespaceA_ServiceARequest>,
              serializer: some MessageSerializer<NamespaceA_ServiceARequest>,
              deserializer: some MessageDeserializer<NamespaceA_ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Stream<NamespaceA_ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable {
              try await self.client.serverStreaming(
                  request: request,
                  descriptor: NamespaceA_ServiceA.Method.MethodB.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .package
    )
  }

  func testClientCodeTranslatorNoNamespaceService() throws {
    let method = MethodDescriptor(
      documentation: "/// Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "ServiceARequest",
      outputType: "ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol ServiceAClientProtocol: Sendable {
          /// Documentation for MethodA
          func methodA<R>(
              request: ClientRequest.Single<ServiceARequest>,
              serializer: some MessageSerializer<ServiceARequest>,
              deserializer: some MessageDeserializer<ServiceAResponse>,
              options: CallOptions,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceAResponse>) async throws -> R
          ) async throws -> R where R: Sendable
      }
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceA.ClientProtocol {
          internal func methodA<R>(
              request: ClientRequest.Single<ServiceARequest>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.methodA(
                  request: request,
                  serializer: ProtobufSerializer<ServiceARequest>(),
                  deserializer: ProtobufDeserializer<ServiceAResponse>(),
                  options: options,
                  body
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal struct ServiceAClient: ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          internal init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
          
          /// Documentation for MethodA
          internal func methodA<R>(
              request: ClientRequest.Single<ServiceARequest>,
              serializer: some MessageSerializer<ServiceARequest>,
              deserializer: some MessageDeserializer<ServiceAResponse>,
              options: CallOptions = .defaults,
              _ body: @Sendable @escaping (ClientResponse.Single<ServiceAResponse>) async throws -> R = {
                  try $0.message
              }
          ) async throws -> R where R: Sendable {
              try await self.client.unary(
                  request: request,
                  descriptor: ServiceA.Method.MethodA.descriptor,
                  serializer: serializer,
                  deserializer: deserializer,
                  options: options,
                  handler: body
              )
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .internal
    )
  }

  func testClientCodeTranslatorMultipleServices() throws {
    let serviceA = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: ""),
      namespace: Name(
        base: "nammespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: ""
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: """
        /// Documentation for ServiceB
        ///
        /// Line 2
        """,
      name: Name(base: "ServiceB", generatedUpperCase: "ServiceB", generatedLowerCase: ""),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceAClientProtocol: Sendable {}
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ClientProtocol {
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct NamespaceA_ServiceAClient: NamespaceA_ServiceA.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      /// Documentation for ServiceB
      ///
      /// Line 2
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol ServiceBClientProtocol: Sendable {}
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceB.ClientProtocol {
      }
      /// Documentation for ServiceB
      ///
      /// Line 2
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public struct ServiceBClient: ServiceB.ClientProtocol {
          private let client: GRPCCore.GRPCClient
          
          public init(client: GRPCCore.GRPCClient) {
              self.client = client
          }
      }
      """

    try self.assertClientCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  private func assertClientCodeTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    accessLevel: SourceGenerator.Configuration.AccessLevel
  ) throws {
    let translator = ClientCodeTranslator(accessLevel: accessLevel)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}

#endif  // os(macOS) || os(Linux)
