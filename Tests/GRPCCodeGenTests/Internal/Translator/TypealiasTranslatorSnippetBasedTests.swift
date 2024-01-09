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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {
                  public enum MethodA {
                      public typealias Input = NamespaceA_ServiceARequest
                      public typealias Output = NamespaceA_ServiceAResponse
                      public static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
              }
              public static let methods: [MethodDescriptor] = [
                  Methods.MethodA.descriptor
              ]
              public typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              public typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              public typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              public typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .public
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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {}
              public static let methods: [MethodDescriptor] = []
              public typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              public typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              public typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              public typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .public
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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {}
              public static let methods: [MethodDescriptor] = []
              public typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              public typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: true,
      visibility: .public
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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {}
              public static let methods: [MethodDescriptor] = []
              public typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              public typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: false,
      visibility: .public
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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {}
              public static let methods: [MethodDescriptor] = []
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: false,
      visibility: .public
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
      public enum ServiceA {
          public enum Methods {
              public enum MethodA {
                  public typealias Input = ServiceARequest
                  public typealias Output = ServiceAResponse
                  public static let descriptor = MethodDescriptor(
                      service: "ServiceA",
                      method: "MethodA"
                  )
              }
          }
          public static let methods: [MethodDescriptor] = [
              Methods.MethodA.descriptor
          ]
          public typealias StreamingServiceProtocol = ServiceAServiceStreamingProtocol
          public typealias ServiceProtocol = ServiceAServiceProtocol
          public typealias ClientProtocol = ServiceAClientProtocol
          public typealias Client = ServiceAClient
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .public
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
      public enum namespaceA {
          public enum ServiceA {
              public enum Methods {
                  public enum MethodA {
                      public typealias Input = NamespaceA_ServiceARequest
                      public typealias Output = NamespaceA_ServiceAResponse
                      public static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodA"
                      )
                  }
                  public enum MethodB {
                      public typealias Input = NamespaceA_ServiceARequest
                      public typealias Output = NamespaceA_ServiceAResponse
                      public static let descriptor = MethodDescriptor(
                          service: "namespaceA.ServiceA",
                          method: "MethodB"
                      )
                  }
              }
              public static let methods: [MethodDescriptor] = [
                  Methods.MethodA.descriptor,
                  Methods.MethodB.descriptor
              ]
              public typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              public typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              public typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              public typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .public
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
      fileprivate enum namespaceA {
          fileprivate enum ServiceA {
              fileprivate enum Methods {}
              fileprivate static let methods: [MethodDescriptor] = []
              fileprivate typealias StreamingServiceProtocol = namespaceA_ServiceAServiceStreamingProtocol
              fileprivate typealias ServiceProtocol = namespaceA_ServiceAServiceProtocol
              fileprivate typealias ClientProtocol = namespaceA_ServiceAClientProtocol
              fileprivate typealias Client = namespaceA_ServiceAClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .fileprivate
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
      private enum namespacea {
          private enum AService {
              private enum Methods {}
              private static let methods: [MethodDescriptor] = []
              private typealias StreamingServiceProtocol = namespacea_AServiceServiceStreamingProtocol
              private typealias ServiceProtocol = namespacea_AServiceServiceProtocol
              private typealias ClientProtocol = namespacea_AServiceClientProtocol
              private typealias Client = namespacea_AServiceClient
          }
          private enum BService {
              private enum Methods {}
              private static let methods: [MethodDescriptor] = []
              private typealias StreamingServiceProtocol = namespacea_BServiceServiceStreamingProtocol
              private typealias ServiceProtocol = namespacea_BServiceServiceProtocol
              private typealias ClientProtocol = namespacea_BServiceClientProtocol
              private typealias Client = namespacea_BServiceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .private
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
      package enum AService {
          package enum Methods {}
          package static let methods: [MethodDescriptor] = []
          package typealias StreamingServiceProtocol = AServiceServiceStreamingProtocol
          package typealias ServiceProtocol = AServiceServiceProtocol
          package typealias ClientProtocol = AServiceClientProtocol
          package typealias Client = AServiceClient
      }
      package enum BService {
          package enum Methods {}
          package static let methods: [MethodDescriptor] = []
          package typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          package typealias ServiceProtocol = BServiceServiceProtocol
          package typealias ClientProtocol = BServiceClientProtocol
          package typealias Client = BServiceClient
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .package
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
      internal enum anamespace {
          internal enum AService {
              internal enum Methods {}
              internal static let methods: [MethodDescriptor] = []
              internal typealias StreamingServiceProtocol = anamespace_AServiceServiceStreamingProtocol
              internal typealias ServiceProtocol = anamespace_AServiceServiceProtocol
              internal typealias ClientProtocol = anamespace_AServiceClientProtocol
              internal typealias Client = anamespace_AServiceClient
          }
      }
      internal enum bnamespace {
          internal enum BService {
              internal enum Methods {}
              internal static let methods: [MethodDescriptor] = []
              internal typealias StreamingServiceProtocol = bnamespace_BServiceServiceStreamingProtocol
              internal typealias ServiceProtocol = bnamespace_BServiceServiceProtocol
              internal typealias ClientProtocol = bnamespace_BServiceClientProtocol
              internal typealias Client = bnamespace_BServiceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .internal
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
      public enum BService {
          public enum Methods {}
          public static let methods: [MethodDescriptor] = []
          public typealias StreamingServiceProtocol = BServiceServiceStreamingProtocol
          public typealias ServiceProtocol = BServiceServiceProtocol
          public typealias ClientProtocol = BServiceClientProtocol
          public typealias Client = BServiceClient
      }
      public enum anamespace {
          public enum AService {
              public enum Methods {}
              public static let methods: [MethodDescriptor] = []
              public typealias StreamingServiceProtocol = anamespace_AServiceServiceStreamingProtocol
              public typealias ServiceProtocol = anamespace_AServiceServiceProtocol
              public typealias ClientProtocol = anamespace_AServiceClientProtocol
              public typealias Client = anamespace_AServiceClient
          }
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      visibility: .public
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
    let translator = TypealiasTranslator(client: true, server: true, visibility: .public)
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
    let translator = TypealiasTranslator(client: true, server: true, visibility: .public)
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
    let translator = TypealiasTranslator(client: true, server: true, visibility: .public)
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
    let translator = TypealiasTranslator(client: true, server: true, visibility: .public)
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
    server: Bool,
    visibility: Configuration.Visibility
  ) throws {
    let translator = TypealiasTranslator(client: client, server: server, visibility: visibility)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}

#endif  // os(macOS) || os(Linux)
