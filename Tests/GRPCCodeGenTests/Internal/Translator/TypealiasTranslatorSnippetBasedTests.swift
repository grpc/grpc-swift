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

final class TypealiasTranslatorSnippetBasedTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testTypealiasTranslator() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
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
                  enum methodA {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
              }
              static let methods: [MethodDescriptor] = [
                  Methods.methodA.descriptor
              ]
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorNoMethodsServiceClientAndServer() throws {
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
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorServer() throws {
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
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: true
    )
  }

  func testTypealiasTranslatorClient() throws {
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
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: false
    )
  }

  func testTypealiasTranslatorNoClientNoServer() throws {
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
              enum Methods {}
              static let methods: [MethodDescriptor] = []
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: false
    )
  }

  func testTypealiasTranslatorEmptyNamespace() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
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
              enum methodA {
                  typealias Input = ServiceARequest
                  typealias Output = ServiceAResponse
                  static let descriptor = MethodDescriptor(
                      service: "ServiceA",
                      method: "MethodA"
                  )
              }
          }
          static let methods: [MethodDescriptor] = [
              Methods.methodA.descriptor
          ]
          typealias StreamingServiceProtocol = ServiceAServiceStreamingProtocol
          typealias ServiceProtocol = ServiceAServiceProtocol
          typealias ClientProtocol = ServiceAClientProtocol
          typealias Client = ServiceAClient
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorCheckMethodsOrder() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "MethodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodB",
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
                  enum methodA {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
                  enum methodB {
                      typealias Input = NamespaceA_ServiceARequest
                      typealias Output = NamespaceA_ServiceAResponse
                      static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodB"
                      )
                  }
              }
              static let methods: [MethodDescriptor] = [
                  Methods.methodA.descriptor,
                  Methods.methodB.descriptor
              ]
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
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
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorServiceAlphabeticalOrder() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      namespace: "namespacea",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "namespacea",
      methods: []
    )

    let expectedSwift =
      """
      enum namespacea {
          enum Aservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespacea_AserviceServiceStreamingProtocol
              typealias ServiceProtocol = namespacea_AserviceServiceProtocol
              typealias ClientProtocol = namespacea_AserviceClientProtocol
              typealias Client = namespacea_AserviceClient
          }
          enum Bservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = namespacea_BserviceServiceStreamingProtocol
              typealias ServiceProtocol = namespacea_BserviceServiceProtocol
              typealias ClientProtocol = namespacea_BserviceClientProtocol
              typealias Client = namespacea_BserviceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorServiceAlphabeticalOrderNoNamespace() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      namespace: "",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "",
      methods: []
    )

    let expectedSwift =
      """
      enum Aservice {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = AserviceServiceStreamingProtocol
          typealias ServiceProtocol = AserviceServiceProtocol
          typealias ClientProtocol = AserviceClientProtocol
          typealias Client = AserviceClient
      }
      enum Bservice {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BserviceServiceStreamingProtocol
          typealias ServiceProtocol = BserviceServiceProtocol
          typealias ClientProtocol = BserviceClientProtocol
          typealias Client = BserviceClient
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
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
          enum Aservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = anamespace_AserviceServiceStreamingProtocol
              typealias ServiceProtocol = anamespace_AserviceServiceProtocol
              typealias ClientProtocol = anamespace_AserviceClientProtocol
              typealias Client = anamespace_AserviceClient
          }
      }
      enum bnamespace {
          enum Bservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = bnamespace_BserviceServiceStreamingProtocol
              typealias ServiceProtocol = bnamespace_BserviceServiceProtocol
              typealias ClientProtocol = bnamespace_BserviceClientProtocol
              typealias Client = bnamespace_BserviceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
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
      enum Bservice {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BserviceServiceStreamingProtocol
          typealias ServiceProtocol = BserviceServiceProtocol
          typealias ClientProtocol = BserviceClientProtocol
          typealias Client = BserviceClient
      }
      enum anamespace {
          enum Aservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = anamespace_AserviceServiceStreamingProtocol
              typealias ServiceProtocol = anamespace_AserviceServiceProtocol
              typealias ClientProtocol = anamespace_AserviceClientProtocol
              typealias Client = anamespace_AserviceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      client: true,
      server: true
    )
  }

  func testTypealiasTranslatorSameNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = TypealiasTranslator(client: true, server: true)
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(from: codeGenerationRequest)
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services in an empty namespace must have unique names. \
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
      namespace: "namespacea",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = TypealiasTranslator(client: true, server: true)
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(from: codeGenerationRequest)
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services within the same namespace must have unique names. \
            AService is used as a name for multiple services in the namespacea namespace.
            """
        )
      )
    }
  }

  func testTypealiasTranslatorSameNameMethodsSameServiceError() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: "MethodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "namespacea",
      methods: [methodA, methodA]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = TypealiasTranslator(client: true, server: true)
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(from: codeGenerationRequest)
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique names. \
            MethodA is used as a name for multiple methods of the AService service.
            """
        )
      )
    }
  }

  func testTypealiasTranslatorSameNameNoNamespaceServiceAndNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "SameName",
      namespace: "",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      namespace: "SameName",
      methods: []
    )
    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = TypealiasTranslator(client: true, server: true)
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(from: codeGenerationRequest)
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services with no namespace must not have the same names as the namespaces. \
            SameName is used as a name for a service with no namespace and a namespace.
            """
        )
      )
    }
  }
}

extension TypealiasTranslatorSnippetBasedTests {
  private func assertTypealiasTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    client: Bool,
    server: Bool
  ) throws {
    let translator = TypealiasTranslator(client: client, server: server)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}

#endif  // os(macOS) || os(Linux)
