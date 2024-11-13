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

  func testTypealiasTranslatorCheckMethodsOrder() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: Name(base: "MethodA", generatedUpperCase: "MethodA", generatedLowerCase: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodB",
      name: Name(base: "MethodB", generatedUpperCase: "MethodB", generatedLowerCase: "methodB"),
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
      methods: [methodA, methodB]
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
              public enum MethodB {
                  public typealias Input = NamespaceA_ServiceARequest
                  public typealias Output = NamespaceA_ServiceAResponse
                  public static let descriptor = GRPCCore.MethodDescriptor(
                      service: NamespaceA_ServiceA.descriptor.fullyQualifiedService,
                      method: "MethodB"
                  )
              }
              public static let descriptors: [GRPCCore.MethodDescriptor] = [
                  MethodA.descriptor,
                  MethodB.descriptor
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

  func testTypealiasTranslatorServiceAlphabeticalOrder() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: Name(base: "BService", generatedUpperCase: "Bservice", generatedLowerCase: "bservice"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: Name(base: "AService", generatedUpperCase: "Aservice", generatedLowerCase: "aservice"),
      namespace: Name(
        base: "namespaceA",
        generatedUpperCase: "NamespaceA",
        generatedLowerCase: "namespaceA"
      ),
      methods: []
    )

    let expectedSwift =
      """
      public enum NamespaceA_Aservice {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_AService
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = NamespaceA_Aservice_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = NamespaceA_Aservice_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = NamespaceA_Aservice_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = NamespaceA_Aservice_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_AService = Self(
              package: "namespaceA",
              service: "AService"
          )
      }
      public enum NamespaceA_Bservice {
          public static let descriptor = GRPCCore.ServiceDescriptor.namespaceA_BService
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = NamespaceA_Bservice_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = NamespaceA_Bservice_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = NamespaceA_Bservice_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = NamespaceA_Bservice_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let namespaceA_BService = Self(
              package: "namespaceA",
              service: "BService"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .public
    )
  }

  func testTypealiasTranslatorServiceAlphabeticalOrderNoNamespace() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: Name(base: "BService", generatedUpperCase: "BService", generatedLowerCase: "bservice"),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: Name(base: "AService", generatedUpperCase: "AService", generatedLowerCase: "aservice"),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: []
    )

    let expectedSwift =
      """
      package enum AService {
          package static let descriptor = GRPCCore.ServiceDescriptor.AService
          package enum Method {
              package static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias StreamingServiceProtocol = AService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ServiceProtocol = AService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ClientProtocol = AService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias Client = AService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          package static let AService = Self(
              package: "",
              service: "AService"
          )
      }
      package enum BService {
          package static let descriptor = GRPCCore.ServiceDescriptor.BService
          package enum Method {
              package static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias StreamingServiceProtocol = BService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ServiceProtocol = BService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias ClientProtocol = BService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          package typealias Client = BService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          package static let BService = Self(
              package: "",
              service: "BService"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .package
    )
  }

  func testTypealiasTranslatorNamespaceAlphabeticalOrder() throws {
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: Name(base: "BService", generatedUpperCase: "BService", generatedLowerCase: "bservice"),
      namespace: Name(
        base: "bnamespace",
        generatedUpperCase: "Bnamespace",
        generatedLowerCase: "bnamespace"
      ),
      methods: []
    )

    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: Name(base: "AService", generatedUpperCase: "AService", generatedLowerCase: "aservice"),
      namespace: Name(
        base: "anamespace",
        generatedUpperCase: "Anamespace",
        generatedLowerCase: "anamespace"
      ),
      methods: []
    )

    let expectedSwift =
      """
      internal enum Anamespace_AService {
          internal static let descriptor = GRPCCore.ServiceDescriptor.anamespace_AService
          internal enum Method {
              internal static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias StreamingServiceProtocol = Anamespace_AService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias ServiceProtocol = Anamespace_AService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias ClientProtocol = Anamespace_AService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias Client = Anamespace_AService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          internal static let anamespace_AService = Self(
              package: "anamespace",
              service: "AService"
          )
      }
      internal enum Bnamespace_BService {
          internal static let descriptor = GRPCCore.ServiceDescriptor.bnamespace_BService
          internal enum Method {
              internal static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias StreamingServiceProtocol = Bnamespace_BService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias ServiceProtocol = Bnamespace_BService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias ClientProtocol = Bnamespace_BService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          internal typealias Client = Bnamespace_BService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          internal static let bnamespace_BService = Self(
              package: "bnamespace",
              service: "BService"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceB, serviceA]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .internal
    )
  }

  func testTypealiasTranslatorNamespaceNoNamespaceOrder() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: Name(base: "AService", generatedUpperCase: "AService", generatedLowerCase: "aService"),
      namespace: Name(
        base: "anamespace",
        generatedUpperCase: "Anamespace",
        generatedLowerCase: "anamespace"
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: Name(base: "BService", generatedUpperCase: "BService", generatedLowerCase: "bService"),
      namespace: Name(base: "", generatedUpperCase: "", generatedLowerCase: ""),
      methods: []
    )
    let expectedSwift =
      """
      public enum Anamespace_AService {
          public static let descriptor = GRPCCore.ServiceDescriptor.anamespace_AService
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = Anamespace_AService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = Anamespace_AService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = Anamespace_AService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = Anamespace_AService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let anamespace_AService = Self(
              package: "anamespace",
              service: "AService"
          )
      }
      public enum BService {
          public static let descriptor = GRPCCore.ServiceDescriptor.BService
          public enum Method {
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias StreamingServiceProtocol = BService_StreamingServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ServiceProtocol = BService_ServiceProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias ClientProtocol = BService_ClientProtocol
          @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
          public typealias Client = BService_Client
      }
      extension GRPCCore.ServiceDescriptor {
          public static let BService = Self(
              package: "",
              service: "BService"
          )
      }
      """

    try self.assertTypealiasTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(services: [serviceA, serviceB]),
      expectedSwift: expectedSwift,
      client: true,
      server: true,
      accessLevel: .public
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
