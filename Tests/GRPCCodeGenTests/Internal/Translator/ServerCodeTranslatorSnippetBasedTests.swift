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
  typealias Name = GRPCCodeGen.CodeGenerationRequest.Name

  func testServerCodeTranslatorUnaryMethod() throws {
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
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      public protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for unaryMethod
          func unary(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.Unary.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.Unary.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.Unary.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.Unary.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.Unary.Output>(),
                  handler: { request in
                      try await self.unary(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      public protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for unaryMethod
          func unary(request: ServerRequest.Single<NamespaceA.ServiceA.Method.Unary.Input>) async throws -> ServerResponse.Single<NamespaceA.ServiceA.Method.Unary.Output>
      }
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
          public func unary(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.Unary.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.Unary.Output> {
              let response = try await self.unary(request: ServerRequest.Single(stream: request))
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
      documentation: "/// Documentation for inputStreamingMethod",
      name: Name(
        base: "InputStreamingMethod",
        generatedUpperCase: "InputStreaming",
        generatedLowerCase: "inputStreaming"
      ),
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      package protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.InputStreaming.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.InputStreaming.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.InputStreaming.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.InputStreaming.Output>(),
                  handler: { request in
                      try await self.inputStreaming(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      package protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Single<NamespaceA.ServiceA.Method.InputStreaming.Output>
      }
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
          package func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.InputStreaming.Output> {
              let response = try await self.inputStreaming(request: request)
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
      documentation: "/// Documentation for outputStreamingMethod",
      name: Name(
        base: "OutputStreamingMethod",
        generatedUpperCase: "OutputStreaming",
        generatedLowerCase: "outputStreaming"
      ),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(
        base: "ServiceATest",
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
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      public protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for outputStreamingMethod
          func outputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.OutputStreaming.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.OutputStreaming.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.OutputStreaming.Output>(),
                  handler: { request in
                      try await self.outputStreaming(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      public protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for outputStreamingMethod
          func outputStreaming(request: ServerRequest.Single<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output>
      }
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
          public func outputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output> {
              let response = try await self.outputStreaming(request: ServerRequest.Single(stream: request))
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
      documentation: "/// Documentation for bidirectionalStreamingMethod",
      name: Name(
        base: "BidirectionalStreamingMethod",
        generatedUpperCase: "BidirectionalStreaming",
        generatedLowerCase: "bidirectionalStreaming"
      ),
      isInputStreaming: true,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(
        base: "ServiceATest",
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
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      package protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.BidirectionalStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.BidirectionalStreaming.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.BidirectionalStreaming.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.BidirectionalStreaming.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.BidirectionalStreaming.Output>(),
                  handler: { request in
                      try await self.bidirectionalStreaming(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      package protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.BidirectionalStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.BidirectionalStreaming.Output>
      }
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
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
      documentation: "/// Documentation for inputStreamingMethod",
      name: Name(
        base: "InputStreamingMethod",
        generatedUpperCase: "InputStreaming",
        generatedLowerCase: "inputStreaming"
      ),
      isInputStreaming: true,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let outputStreamingMethod = MethodDescriptor(
      documentation: "/// Documentation for outputStreamingMethod",
      name: Name(
        base: "outputStreamingMethod",
        generatedUpperCase: "OutputStreaming",
        generatedLowerCase: "outputStreaming"
      ),
      isInputStreaming: false,
      isOutputStreaming: true,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(
        base: "ServiceATest",
        generatedUpperCase: "ServiceA",
        generatedLowerCase: "serviceA"
      ),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: [inputStreamingMethod, outputStreamingMethod]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      internal protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.InputStreaming.Output>
          
          /// Documentation for outputStreamingMethod
          func outputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.InputStreaming.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.InputStreaming.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.InputStreaming.Output>(),
                  handler: { request in
                      try await self.inputStreaming(request: request)
                  }
              )
              router.registerHandler(
                  forMethod: NamespaceA.ServiceA.Method.OutputStreaming.descriptor,
                  deserializer: ProtobufDeserializer<NamespaceA.ServiceA.Method.OutputStreaming.Input>(),
                  serializer: ProtobufSerializer<NamespaceA.ServiceA.Method.OutputStreaming.Output>(),
                  handler: { request in
                      try await self.outputStreaming(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      internal protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Single<NamespaceA.ServiceA.Method.InputStreaming.Output>
          
          /// Documentation for outputStreamingMethod
          func outputStreaming(request: ServerRequest.Single<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output>
      }
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
          internal func inputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.InputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.InputStreaming.Output> {
              let response = try await self.inputStreaming(request: request)
              return ServerResponse.Stream(single: response)
          }
          
          internal func outputStreaming(request: ServerRequest.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Input>) async throws -> ServerResponse.Stream<NamespaceA.ServiceA.Method.OutputStreaming.Output> {
              let response = try await self.outputStreaming(request: ServerRequest.Single(stream: request))
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
      documentation: "/// Documentation for MethodA",
      name: Name(base: "methodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "/// Documentation for ServiceA",
      name: Name(
        base: "ServiceATest",
        generatedUpperCase: "ServiceA",
        generatedLowerCase: "serviceA"
      ),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      internal protocol ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for MethodA
          func methodA(request: ServerRequest.Stream<ServiceA.Method.MethodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Method.MethodA.Output>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: ServiceA.Method.MethodA.descriptor,
                  deserializer: ProtobufDeserializer<ServiceA.Method.MethodA.Input>(),
                  serializer: ProtobufSerializer<ServiceA.Method.MethodA.Output>(),
                  handler: { request in
                      try await self.methodA(request: request)
                  }
              )
          }
      }
      /// Documentation for ServiceA
      internal protocol ServiceAServiceProtocol: ServiceA.StreamingServiceProtocol {
          /// Documentation for MethodA
          func methodA(request: ServerRequest.Single<ServiceA.Method.MethodA.Input>) async throws -> ServerResponse.Single<ServiceA.Method.MethodA.Output>
      }
      /// Partial conformance to `ServiceAStreamingServiceProtocol`.
      extension ServiceA.ServiceProtocol {
          internal func methodA(request: ServerRequest.Stream<ServiceA.Method.MethodA.Input>) async throws -> ServerResponse.Stream<ServiceA.Method.MethodA.Output> {
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
      documentation: "/// Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "/// Documentation for ServiceB",
      name: Name(base: "ServiceB", generatedUpperCase: "ServiceB", generatedLowerCase: "serviceB"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      /// Documentation for ServiceA
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      public protocol NamespaceA_ServiceAStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceA.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceA
      public protocol NamespaceA_ServiceAServiceProtocol: NamespaceA.ServiceA.StreamingServiceProtocol {}
      /// Partial conformance to `NamespaceA_ServiceAStreamingServiceProtocol`.
      extension NamespaceA.ServiceA.ServiceProtocol {
      }
      /// Documentation for ServiceB
      @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
      public protocol NamespaceA_ServiceBStreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      extension NamespaceA.ServiceB.StreamingServiceProtocol {
          @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceB
      public protocol NamespaceA_ServiceBServiceProtocol: NamespaceA.ServiceB.StreamingServiceProtocol {}
      /// Partial conformance to `NamespaceA_ServiceBStreamingServiceProtocol`.
      extension NamespaceA.ServiceB.ServiceProtocol {
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
