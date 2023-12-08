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

final class SnippetBasedTranslatorTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testTypealiasTranslator() throws {
    let method = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodA",
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
      enum namespaceA {
          enum ServiceA {
              enum Methods {
                  enum MethodA {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
              }
              static let methods: [MethodDescriptor] = [
                  namespaceA.ServiceA.Methods.MethodA.descriptor
              ]
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorEmptyNamespace() throws {
    let method = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodA",
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
      enum ServiceA {
          enum Methods {
              enum MethodA {
                  typealias Input = ServiceARequest
                  typealias Output = ServiceAResponse
                  static let descriptor = MethodDescriptor(
                      service: "ServiceA",
                      method: "MethodA"
                  )
              }
          }
          static let methods: [MethodDescriptor] = [
              ServiceA.Methods.MethodA.descriptor
          ]
          typealias StreamingServiceProtocol = ServiceAServiceStreamingProtocol
          typealias ServiceProtocol = ServiceAServiceProtocol
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorCheckMethodsOrder() throws {
    let methodA = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodB",
      isInputStreaming: false,
      isOutputStreaming: false,
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
      enum namespaceA {
          enum ServiceA {
              enum Methods {
                  enum MethodA {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
                  enum MethodB {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodB"
                      )
                  }
              }
              static let methods: [MethodDescriptor] = [
                  namespaceA.ServiceA.Methods.MethodA.descriptor,
                  namespaceA.ServiceA.Methods.MethodB.descriptor
              ]
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorNoMethodsService() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "ServiceA",
      namespace: "namespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum namespaceA {
          enum ServiceA {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorServiceAlphabeticalOrder() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "BService",
      namespace: "namespaceA",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "AService",
      namespace: "namespaceA",
      methods: []
    )

    let expectedSwift =
      """
      enum namespaceA {
          enum AService {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_AServiceServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_AServiceServiceProtocol
          }
          enum BService {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_BServiceServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_BServiceServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorServiceAlphabeticalOrderNoNamespace() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "BService",
      namespace: "",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: "AService",
      namespace: "",
      methods: []
    )

    let expectedSwift =
      """
      enum AService {
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = AServiceServiceStreamingProtocol
          typealias ServiceProtocol = AServiceServiceProtocol
      }
      enum BService {
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          typealias ServiceProtocol = BServiceServiceProtocol
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorNamespaceAlphabeticalOrder() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      namespace: "bnamespace",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "anamespace",
      methods: []
    )

    let expectedSwift =
      """
      enum anamespace {
          enum AService {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = anamespace_AServiceServiceStreamingProtocol
              typealias ServiceProtocol = anamespace_AServiceServiceProtocol
          }
      }
      enum bnamespace {
          enum BService {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = bnamespace_BServiceServiceStreamingProtocol
              typealias ServiceProtocol = bnamespace_BServiceServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorNamespaceNoNamespaceOrder() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "anamespace",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      namespace: "",
      methods: []
    )
    let expectedSwift =
      """
      enum BService {
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          typealias ServiceProtocol = BServiceServiceProtocol
      }
      enum anamespace {
          enum AService {
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = anamespace_AServiceServiceStreamingProtocol
              typealias ServiceProtocol = anamespace_AServiceServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: self.makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift
    )
  }

  func testTypealiasTranslatorSameNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "AService",
      namespace: "",
      methods: []
    )

    let codeGenerationRequest = self.makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = TypealiasTranslator()
    self.assertThrowsError(try translator.translate(from: codeGenerationRequest)) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .sameNameServices,
          message: """
            Services with no namespace must have unique names. \
            AService is used as a name for multiple services without namespaces.
            """
        )
      )
    }
  }

  func testTypealiasTranslatorSameNameServicesSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "foo",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "AService",
      namespace: "foo",
      methods: []
    )

    let codeGenerationRequest = self.makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = TypealiasTranslator()
    self.assertThrowsError(try translator.translate(from: codeGenerationRequest)) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .sameNameServices,
          message: """
            Services within the same namespace must have unique names. \
            AService is used as a name for multiple services in the foo namespace.
            """
        )
      )
    }
  }

  func testTypealiasTranslatorSameNameMethodsSameServiceError() throws {
    let methodA = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Mock documentation",
      name: "MethodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for Service",
      name: "AService",
      namespace: "namespace",
      methods: [methodA, methodB]
    )

    let codeGenerationRequest = self.makeCodeGenerationRequest(services: [service])
    let translator = TypealiasTranslator()
    self.assertThrowsError(try translator.translate(from: codeGenerationRequest)) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .sameNameMethods,
          message: """
            Methods of a service must have unique names. \
            MethodA is used as a name for multiple methods of the AService service.
            """
        )
      )
    }
  }
}

extension SnippetBasedTranslatorTests {
  private func assertTypealiasTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = TypealiasTranslator()
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try TestFunctions.XCTAssertEqualWithDiff(contents, expectedSwift)
  }

  private func assertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    _ errorHandler: (CodeGenError) -> Void
  ) {
    XCTAssertThrowsError(try expression()) { error in
      guard let error = error as? CodeGenError else {
        return XCTFail("Error had unexpected type '\(type(of: error))'")
      }
      errorHandler(error)
    }
  }
}

extension SnippetBasedTranslatorTests {
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
}
