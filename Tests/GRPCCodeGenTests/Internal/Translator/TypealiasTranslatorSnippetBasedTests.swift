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
      enum NamespaceA {
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
                  Methods.MethodA.descriptor
              ]
              typealias StreamingServiceProtocol = NamespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = NamespaceA_ServiceAClientProtocol
              typealias Client = NamespaceA_ServiceAClient
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
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum NamespaceA {
          enum ServiceA {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = NamespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = NamespaceA_ServiceAClientProtocol
              typealias Client = NamespaceA_ServiceAClient
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
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum NamespaceA {
          enum ServiceA {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = NamespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_ServiceAServiceProtocol
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
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum NamespaceA {
          enum ServiceA {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias ClientProtocol = NamespaceA_ServiceAClientProtocol
              typealias Client = NamespaceA_ServiceAClient
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
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum NamespaceA {
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
              Methods.MethodA.descriptor
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
      generatedName: "MethodA",
      signatureName: "methodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodB",
      name: "MethodB",
      generatedName: "MethodB",
      signatureName: "methodB",
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
      methods: [methodA, methodB]
    )
    let expectedSwift =
      """
      enum NamespaceA {
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
                  Methods.MethodA.descriptor,
                  Methods.MethodB.descriptor
              ]
              typealias StreamingServiceProtocol = NamespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = NamespaceA_ServiceAClientProtocol
              typealias Client = NamespaceA_ServiceAClient
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
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let expectedSwift =
      """
      enum NamespaceA {
          enum ServiceA {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = NamespaceA_ServiceAServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_ServiceAServiceProtocol
              typealias ClientProtocol = NamespaceA_ServiceAClientProtocol
              typealias Client = NamespaceA_ServiceAClient
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
      generatedName: "Bservice",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "Aservice",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )

    let expectedSwift =
      """
      enum NamespaceA {
          enum Aservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = NamespaceA_AserviceServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_AserviceServiceProtocol
              typealias ClientProtocol = NamespaceA_AserviceClientProtocol
              typealias Client = NamespaceA_AserviceClient
          }
          enum Bservice {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = NamespaceA_BserviceServiceStreamingProtocol
              typealias ServiceProtocol = NamespaceA_BserviceServiceProtocol
              typealias ClientProtocol = NamespaceA_BserviceClientProtocol
              typealias Client = NamespaceA_BserviceClient
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
      generatedName: "BService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )

    let expectedSwift =
      """
      enum AService {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = AServiceServiceStreamingProtocol
          typealias ServiceProtocol = AServiceServiceProtocol
          typealias ClientProtocol = AServiceClientProtocol
          typealias Client = AServiceClient
      }
      enum BService {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          typealias ServiceProtocol = BServiceServiceProtocol
          typealias ClientProtocol = BServiceClientProtocol
          typealias Client = BServiceClient
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
      generatedName: "BService",
      namespace: "bnamespace",
      generatedNamespace: "Bnamespace",
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "anamespace",
      generatedNamespace: "Anamespace",
      methods: []
    )

    let expectedSwift =
      """
      enum Anamespace {
          enum AService {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = Anamespace_AServiceServiceStreamingProtocol
              typealias ServiceProtocol = Anamespace_AServiceServiceProtocol
              typealias ClientProtocol = Anamespace_AServiceClientProtocol
              typealias Client = Anamespace_AServiceClient
          }
      }
      enum Bnamespace {
          enum BService {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = Bnamespace_BServiceServiceStreamingProtocol
              typealias ServiceProtocol = Bnamespace_BServiceServiceProtocol
              typealias ClientProtocol = Bnamespace_BServiceClientProtocol
              typealias Client = Bnamespace_BServiceClient
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
      generatedName: "AService",
      namespace: "anamespace",
      generatedNamespace: "Anamespace",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      generatedName: "BService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )
    let expectedSwift =
      """
      enum BService {
          enum Methods {}
          static let methods: [MethodDescriptor] = []
          typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          typealias ServiceProtocol = BServiceServiceProtocol
          typealias ClientProtocol = BServiceClientProtocol
          typealias Client = BServiceClient
      }
      enum Anamespace {
          enum AService {
              enum Methods {}
              static let methods: [MethodDescriptor] = []
              typealias StreamingServiceProtocol = Anamespace_AServiceServiceStreamingProtocol
              typealias ServiceProtocol = Anamespace_AServiceServiceProtocol
              typealias ClientProtocol = Anamespace_AServiceClientProtocol
              typealias Client = Anamespace_AServiceClient
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
