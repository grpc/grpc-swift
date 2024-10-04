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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA_ServiceA.Method.InputStreaming.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.inputStreaming(
                          request: request,
                          context: context
                      )
                  }
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceA_ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
          package func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.inputStreaming(
                  request: request,
                  context: context
              )
              return GRPCCore.StreamingServerResponse(single: response)
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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for outputStreamingMethod
          func outputStreaming(
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
                  forMethod: NamespaceA_ServiceA.Method.OutputStreaming.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.outputStreaming(
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
          /// Documentation for outputStreamingMethod
          func outputStreaming(
              request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
          public func outputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.outputStreaming(
                  request: GRPCCore.ServerRequest(stream: request),
                  context: context
              )
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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA_ServiceA.Method.BidirectionalStreaming.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.bidirectionalStreaming(
                          request: request,
                          context: context
                      )
                  }
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      package protocol NamespaceA_ServiceA_ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {
          /// Documentation for bidirectionalStreamingMethod
          func bidirectionalStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for inputStreamingMethod
          func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
          
          /// Documentation for outputStreamingMethod
          func outputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: NamespaceA_ServiceA.Method.InputStreaming.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.inputStreaming(
                          request: request,
                          context: context
                      )
                  }
              )
              router.registerHandler(
                  forMethod: NamespaceA_ServiceA.Method.OutputStreaming.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.outputStreaming(
                          request: request,
                          context: context
                      )
                  }
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol NamespaceA_ServiceA_ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {
          /// Documentation for inputStreamingMethod
          func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>
          
          /// Documentation for outputStreamingMethod
          func outputStreaming(
              request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
          internal func inputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.inputStreaming(
                  request: request,
                  context: context
              )
              return GRPCCore.StreamingServerResponse(single: response)
          }
          
          internal func outputStreaming(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.outputStreaming(
                  request: GRPCCore.ServerRequest(stream: request),
                  context: context
              )
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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {
          /// Documentation for MethodA
          func methodA(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal func registerMethods(with router: inout GRPCCore.RPCRouter) {
              router.registerHandler(
                  forMethod: ServiceA.Method.MethodA.descriptor,
                  deserializer: GRPCProtobuf.ProtobufDeserializer<NamespaceA_ServiceARequest>(),
                  serializer: GRPCProtobuf.ProtobufSerializer<NamespaceA_ServiceAResponse>(),
                  handler: { request, context in
                      try await self.methodA(
                          request: request,
                          context: context
                      )
                  }
              )
          }
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      internal protocol ServiceA_ServiceProtocol: ServiceA.StreamingServiceProtocol {
          /// Documentation for MethodA
          func methodA(
              request: GRPCCore.ServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.ServerResponse<NamespaceA_ServiceAResponse>
      }
      /// Partial conformance to `ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension ServiceA.ServiceProtocol {
          internal func methodA(
              request: GRPCCore.StreamingServerRequest<NamespaceA_ServiceARequest>,
              context: GRPCCore.ServerContext
          ) async throws -> GRPCCore.StreamingServerResponse<NamespaceA_ServiceAResponse> {
              let response = try await self.methodA(
                  request: GRPCCore.ServerRequest(stream: request),
                  context: context
              )
              return GRPCCore.StreamingServerResponse(single: response)
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
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceA
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceA_ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {}
      /// Partial conformance to `NamespaceA_ServiceA_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
      }
      /// Documentation for ServiceB
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceB_StreamingServiceProtocol: GRPCCore.RegistrableRPCService {}
      /// Conformance to `GRPCCore.RegistrableRPCService`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceB.StreamingServiceProtocol {
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public func registerMethods(with router: inout GRPCCore.RPCRouter) {}
      }
      /// Documentation for ServiceB
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public protocol NamespaceA_ServiceB_ServiceProtocol: NamespaceA_ServiceB.StreamingServiceProtocol {}
      /// Partial conformance to `NamespaceA_ServiceB_StreamingServiceProtocol`.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceB.ServiceProtocol {
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
    accessLevel: SourceGenerator.Config.AccessLevel
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
