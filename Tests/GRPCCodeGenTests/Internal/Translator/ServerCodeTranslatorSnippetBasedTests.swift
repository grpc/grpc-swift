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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func unaryMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.unaryMethod.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.unaryMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.unaryMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.unaryMethod.Output>(),
                  handler: { request in
                      try await self.unaryMethod(request)
                  }
              )
          }
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          func unaryMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.unaryMethod.Output>
      }
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
          func unaryMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.unaryMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.unaryMethod.Output> {
              let response = try await self.unaryMethod(request: ServerRequest.Single(stream: request))
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.inputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.inputStreamingMethod(request)
                  }
              )
          }
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
      }
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output> {
              let response = try await self.inputStreamingMethod(request: request)
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.outputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.outputStreamingMethod(request)
                  }
              )
          }
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          func outputStreamingMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output> {
              let response = try await self.outputStreamingMethod(request: ServerRequest.Single(stream: request))
              return response
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func bidirectionalStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>(),
                  handler: { request in
                      try await self.bidirectionalStreamingMethod(request)
                  }
              )
          }
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          func bidirectionalStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.bidirectionalStreamingMethod.Output>
      }
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.inputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.inputStreamingMethod(request)
                  }
              )
              router.registerHandler(
                  for: namespaceA.ServiceA.Methods.outputStreamingMethod.descriptor,
                  deserializer: ProtobufDeserializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>(),
                  serializer: ProtobufSerializer<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>(),
                  handler: { request in
                      try await self.outputStreamingMethod(request)
                  }
              )
          }
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Single<namespaceA.ServiceA.Methods.inputStreamingMethod.Output>
          func outputStreamingMethod(request: ServerRequest.Single<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output>
      }
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
          func inputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.inputStreamingMethod.Output> {
              let response = try await self.inputStreamingMethod(request: request)
              return ServerResponse.Stream(single: response)
          }
          func outputStreamingMethod(request: ServerRequest.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Input>) async throws -> ServerResponse.Stream<namespaceA.ServiceA.Methods.outputStreamingMethod.Output> {
              let response = try await self.outputStreamingMethod(request: ServerRequest.Single(stream: request))
              return response
          }
      }
      """

    try assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          func methodA(request: ServerRequest.Stream<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Methods.methodA.Output>
      }
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {
              router.registerHandler(
                  for: ServiceA.Methods.methodA.descriptor,
                  deserializer: ProtobufDeserializer<ServiceA.Methods.methodA.Input>(),
                  serializer: ProtobufSerializer<ServiceA.Methods.methodA.Output>(),
                  handler: { request in
                      try await self.methodA(request)
                  }
              )
          }
      }
      protocol ServiceAServiceProtocol: ServiceA.StreamingServiceProtocol {
          func methodA(request: ServerRequest.Single<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Single<ServiceA.Methods.methodA.Output>
      }
      // Generated partial conformance to `ServiceAStreamingServiceProtocol`.
      public extension ServiceA.ServiceProtocol {
          func methodA(request: ServerRequest.Stream<ServiceA.Methods.methodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Methods.methodA.Output> {
              let response = try await self.methodA(request: ServerRequest.Single(stream: request))
              return ServerResponse.Stream(single: response)
          }
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
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
      protocol namespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceA.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {}
      }
      protocol namespaceA_ServiceAServiceProtocol: namespaceA.ServiceA.StreamingServiceProtocol {}
      // Generated partial conformance to `namespaceA_ServiceAStreamingServiceProtocol`.
      public extension namespaceA.ServiceA.ServiceProtocol {
      }
      protocol namespaceA_ServiceBStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      // Generated conformance to `GRPCCore.RegistrableRPCService`.
      public extension namespaceA.ServiceB.StreamingServiceProtocol {
          func registerRPCs(with router: inout RPCRouter) {}
      }
      protocol namespaceA_ServiceBServiceProtocol: namespaceA.ServiceB.StreamingServiceProtocol {}
      // Generated partial conformance to `namespaceA_ServiceBStreamingServiceProtocol`.
      public extension namespaceA.ServiceB.ServiceProtocol {
      }
      """

    try self.assertServerCodeTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift
    )
  }

  private func assertServerCodeTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = ServerCodeTranslator()
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}
