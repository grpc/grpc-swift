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

final class ServerCodeTranslatorSnippetBasedTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testServerCodeTranslatorUnaryMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for unaryMethod",
      name: "unaryMethod",
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
      public protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for unaryMethod
          func unaryMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.unaryMethod.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.unaryMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.unaryMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.unaryMethod.Output>(),
                  handler: { request in
                      try await self.unaryMethod(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      public protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for unaryMethod
          func unaryMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.unaryMethod.Output>
      }
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
          public func unaryMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.unaryMethod.Output> {
              let response = try await self.unaryMethod(request: ServerRequest.Single(stream: request))
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testServerCodeTranslatorInputStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for inputStreamingMethod",
      name: "inputStreamingMethod",
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
      package protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.inputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.inputStreamingMethod(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      package protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
      }
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
          package func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output> {
              let response = try await self.inputStreamingMethod(request: request)
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .package
    )
  }

  func testServerCodeTranslatorOutputStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for outputStreamingMethod",
      name: "outputStreamingMethod",
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
      public protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for outputStreamingMethod
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.outputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.outputStreamingMethod(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      public protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for outputStreamingMethod
          func outputStreamingMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
          public func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output> {
              let response = try await self.outputStreamingMethod(request: ServerRequest.Single(stream: request))
              return response
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  func testServerCodeTranslatorBidirectionalStreamingMethod() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for bidirectionalStreamingMethod",
      name: "bidirectionalStreamingMethod",
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
      package protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>(),
                  handler: { request in
                      try await self.bidirectionalStreamingMethod(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      package protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>
      }
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .package
    )
  }

  func testServerCodeTranslatorMultipleMethods() throws {
    let inputStreamingMethod = MethodDescriptor(
      documentation: "Documentation for inputStreamingMethod",
      name: "inputStreamingMethod",
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let outputStreamingMethod = MethodDescriptor(
      documentation: "Documentation for outputStreamingMethod",
      name: "outputStreamingMethod",
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "namespaceA",
      methods: [inputStreamingMethod, outputStreamingMethod]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      internal protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
          /// Documentation for outputStreamingMethod
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.inputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.inputStreamingMethod(request: request)
                  }
              )
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.outputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.outputStreamingMethod(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      internal protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
          /// Documentation for outputStreamingMethod
          func outputStreamingMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
          internal func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output> {
              let response = try await self.inputStreamingMethod(request: request)
              return ServerResponse.Stream(single: response)
          }
          internal func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output> {
              let response = try await self.outputStreamingMethod(request: ServerRequest.Single(stream: request))
              return response
          }
      }
      """

    try assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .internal
    )
  }

  func testServerCodeTranslatorNoNamespaceService() throws {
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
      namespace: "",
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      internal protocol ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for MethodA
          func methodA(request: ServerRequest.Stream<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Methods.methodA.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension ServiceA.StreamingServiceProtocol {
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  for: ServiceA.Methods.methodA.descriptor,
                  deserializer: ProtobufDeserializer<ServiceA.Methods.methodA.Input>(),
                  serializer: ProtobufSerializer<ServiceA.Methods.methodA.Output>(),
                  handler: { request in
                      try await self.methodA(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      internal protocol ServiceAServiceProtocol: ServiceA.StreamingServiceProtocol {
          /// Documentation for MethodA
          func methodA(request: ServerRequest.Single<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Single<ServiceA.Methods.methodA.Output>
      }
      /// Partial conformance to `ServiceAStreamingServiceProtocol`.
      extension ServiceA.ServiceProtocol {
          internal func methodA(request: ServerRequest.Stream<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Methods.methodA.Output> {
              let response = try await self.methodA(request: ServerRequest.Single(stream: request))
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      accessLevel: .internal
    )
  }

  func testServerCodeTranslatorMoreServicesOrder() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "namespaceA",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for ServiceB",
      name: "ServiceB",
      namespace: "namespaceA",
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      public protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceA.StreamingServiceProtocol {
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceA
      public protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {}
      /// Partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      extension namespaceA.ServiceA.ServiceProtocol {
      }
      /// Documentation for ServiceB
      public protocol namespaceA_ServiceBStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension namespaceA.ServiceB.StreamingServiceProtocol {
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceB
      public protocol namespaceA_ServiceBServiceProtocol: namespaceA.ServiceB.StreamingServiceProtocol {}
      /// Partial conformance to `namespaceA_ServiceBStreamingServiceProtocol`.
      extension namespaceA.ServiceB.ServiceProtocol {
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      accessLevel: .public
    )
  }

  private func assertServerCodeTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    accessLevel: SourceGenerator.Configuration.AccessLevel
  ) throws {
    let translator = ServerCodeTranslator(accessLevel: accessLevel)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}

#endif  // os(macOS) || os(Linux)
