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
  func testTypealiasTranslator() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
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
      public enum NamespaceA_ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          public enum Method {
              public enum MethodA {
                  public typealias Input = NamespaceA_ServiceARequest
                  public typealias Output = NamespaceA_ServiceAResponse
                  public static let descriptor = GRPCCore.MethodDescriptor(
                      service: NamespaceA_ServiceA.descriptor.fullyQualifiedService,
                      method: "MethodA"
                  )
              }
              public static let descriptors: [GRPCCore.MethodDescriptor] = [
                  MethodA.descriptor
              ]
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = NamespaceA_ServiceA_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = NamespaceA_ServiceA_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = NamespaceA_ServiceA_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = NamespaceA_ServiceA_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorNoMethodsServiceClientAndServer() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      public enum NamespaceA_ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = NamespaceA_ServiceA_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = NamespaceA_ServiceA_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = NamespaceA_ServiceA_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = NamespaceA_ServiceA_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorServer() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      public enum NamespaceA_ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = NamespaceA_ServiceA_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = NamespaceA_ServiceA_ServiceProtocol
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: true,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorClient() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      public enum NamespaceA_ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = NamespaceA_ServiceA_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = NamespaceA_ServiceA_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: false,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorNoClientNoServer() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      public enum NamespaceA_ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: false,
      server: false,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorEmptyNamespace() throws {
    let method = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "ServiceARequest",
      outputType: "ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: [method]
    )
    let expectedSwift =
      """
      public enum ServiceA {
          public static let descriptor = GRPCCore.ServiceDescriptor.ServiceA
          public enum Method {
              public enum MethodA {
                  public typealias Input = ServiceARequest
                  public typealias Output = ServiceAResponse
                  public static let descriptor = GRPCCore.MethodDescriptor(
                      service: ServiceA.descriptor.fullyQualifiedService,
                      method: "MethodA"
                  )
              }
              public static let descriptors: [GRPCCore.MethodDescriptor] = [
                  MethodA.descriptor
              ]
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = ServiceA_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = ServiceA_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = ServiceA_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = ServiceA_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let ServiceA = Self(
              package: "",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorNoMethodsService() throws {
    let service = ServiceDescriptor(
      documentation: "Documentation for ServiceA",
      name: Name(base: "ServiceA", generatedUpperCase: "ServiceA", generatedLowerCase: "serviceA"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )
    let expectedSwift =
      """
      package enum NamespaceA_ServiceA {
          package static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_ServiceA
          package enum Method {
              package static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias StreamingServiceProtocol = NamespaceA_ServiceA_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ServiceProtocol = NamespaceA_ServiceA_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ClientProtocol = NamespaceA_ServiceA_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias Client = NamespaceA_ServiceA_Client
      }
      extension GRPCCore.ServiceDescriptor {
          package static let namespaceA_ServiceA = Self(
              package: "namespaceA",
              service: "ServiceA"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [service]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .package
    )
  }
}

extension TypealiasTranslatorSnippetBasedTests {
  private func assertTypealiasTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    client: Bool,
    server: Bool,
    accessLevel: SourceGenerator.Config.AccessLevel
  ) throws {
    let translator = TypealiasTranslator(client: client, server: server, accessLevel: accessLevel)
    let codeBlocks = try translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}

#endif  // os(macOS) || os(Linux)
