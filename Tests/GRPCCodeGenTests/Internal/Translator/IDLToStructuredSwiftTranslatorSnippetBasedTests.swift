/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

@available(gRPCSwift 2.0, *)
final class IDLToStructuredSwiftTranslatorSnippetBasedTests: XCTestCase {
  func testGeneration() throws {
    var dependencies = [Dependency]()
    dependencies.append(
      Dependency(module: "Foo", spi: "Secret", accessLevel: .internal)
    )
    dependencies.append(
      Dependency(
        item: .init(kind: .enum, name: "Bar"),
        module: "Foo",
        spi: "Secret",
        accessLevel: .internal
      )
    )

    let serviceA = ServiceDescriptor(
      documentation: "/// Documentation for AService\n",
      name: ServiceName(
        identifyingName: "namespaceA.ServiceA",
        typeName: "NamespaceA_ServiceA",
        propertyName: "namespaceA_ServiceA"
      ),
      methods: []
    )

    let expectedSwift =
      """
      /// Some really exciting license header 2023.

      public import GRPCCore
      @_spi(Secret) internal import Foo
      @_spi(Secret) internal import enum Foo.Bar

      // MARK: - namespaceA.ServiceA

      /// Namespace containing generated types for the "namespaceA.ServiceA" service.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      public enum NamespaceA_ServiceA {
          /// Service descriptor for the "namespaceA.ServiceA" service.
          public static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "namespaceA.ServiceA")
          /// Namespace for method metadata.
          public enum Method {
              /// Descriptors for all methods in the "namespaceA.ServiceA" service.
              public static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
      }

      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension GRPCCore.ServiceDescriptor {
          /// Service descriptor for the "namespaceA.ServiceA" service.
          public static let namespaceA_ServiceA = GRPCCore.ServiceDescriptor(fullyQualifiedService: "namespaceA.ServiceA")
      }

      // MARK: namespaceA.ServiceA (server)

      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA {
          /// Streaming variant of the service protocol for the "namespaceA.ServiceA" service.
          ///
          /// This protocol is the lowest-level of the service protocols generated for this service
          /// giving you the most flexibility over the implementation of your service. This comes at
          /// the cost of more verbose and less strict APIs. Each RPC requires you to implement it in
          /// terms of a request stream and response stream. Where only a single request or response
          /// message is expected, you are responsible for enforcing this invariant is maintained.
          ///
          /// Where possible, prefer using the stricter, less-verbose ``ServiceProtocol``
          /// or ``SimpleServiceProtocol`` instead.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for AService
          public protocol StreamingServiceProtocol: GRPCCore.RegistrableRPCService {}

          /// Service protocol for the "namespaceA.ServiceA" service.
          ///
          /// This protocol is higher level than ``StreamingServiceProtocol`` but lower level than
          /// the ``SimpleServiceProtocol``, it provides access to request and response metadata and
          /// trailing response metadata. If you don't need these then consider using
          /// the ``SimpleServiceProtocol``. If you need fine-grained control over your RPCs then
          /// use ``StreamingServiceProtocol``.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for AService
          public protocol ServiceProtocol: NamespaceA_ServiceA.StreamingServiceProtocol {}

          /// Simple service protocol for the "namespaceA.ServiceA" service.
          ///
          /// This is the highest level protocol for the service. The API is the easiest to use but
          /// doesn't provide access to request or response metadata. If you need access to these
          /// then use ``ServiceProtocol`` instead.
          ///
          /// > Source IDL Documentation:
          /// >
          /// > Documentation for AService
          public protocol SimpleServiceProtocol: NamespaceA_ServiceA.ServiceProtocol {}
      }

      // Default implementation of 'registerMethods(with:)'.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.StreamingServiceProtocol {
          public func registerMethods<Transport>(with router: inout GRPCCore.RPCRouter<Transport>) where Transport: GRPCCore.ServerTransport {}
      }

      // Default implementation of streaming methods from 'StreamingServiceProtocol'.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.ServiceProtocol {
      }

      // Default implementation of methods from 'ServiceProtocol'.
      @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
      extension NamespaceA_ServiceA.SimpleServiceProtocol {
      }
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(
        services: [serviceA],
        dependencies: dependencies
      ),
      expectedSwift: expectedSwift,
      accessLevel: .public,
      server: true
    )
  }

  func testGenerateWithDifferentModuleName() throws {
    let service = ServiceDescriptor(
      documentation: "/// Documentation for FooService\n",
      name: ServiceName(
        identifyingName: "foo.FooService",
        typeName: "Foo_FooService",
        propertyName: "foo_FooService"
      ),
      methods: [
        MethodDescriptor(
          documentation: "",
          name: MethodName(
            identifyingName: "Unary",
            typeName: "Unary",
            functionName: "unary"
          ),
          isInputStreaming: false,
          isOutputStreaming: false,
          inputType: "Foo",
          outputType: "Bar"
        ),
        MethodDescriptor(
          documentation: "",
          name: MethodName(
            identifyingName: "ClientStreaming",
            typeName: "ClientStreaming",
            functionName: "clientStreaming"
          ),
          isInputStreaming: true,
          isOutputStreaming: false,
          inputType: "Foo",
          outputType: "Bar"
        ),
        MethodDescriptor(
          documentation: "",
          name: MethodName(
            identifyingName: "ServerStreaming",
            typeName: "ServerStreaming",
            functionName: "serverStreaming"
          ),
          isInputStreaming: false,
          isOutputStreaming: true,
          inputType: "Foo",
          outputType: "Bar"
        ),
        MethodDescriptor(
          documentation: "",
          name: MethodName(
            identifyingName: "BidiStreaming",
            typeName: "BidiStreaming",
            functionName: "bidiStreaming"
          ),
          isInputStreaming: true,
          isOutputStreaming: true,
          inputType: "Foo",
          outputType: "Bar"
        ),
      ]
    )

    let request = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    let structuredSwift = try translator.translate(
      codeGenerationRequest: request,
      accessLevel: .internal,
      accessLevelOnImports: false,
      client: true,
      server: true,
      grpcCoreModuleName: String("GRPCCore".reversed()),
      availability: .macOS15Aligned
    )
    let renderer = TextBasedRenderer.default
    let sourceFile = try renderer.render(structured: structuredSwift)
    let contents = sourceFile.contents

    XCTAssertFalse(contents.contains("GRPCCore"))
  }

  func testEmptyFileGeneration() throws {
    let expectedSwift =
      """
      /// Some really exciting license header 2023.

      // This file contained no services.
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(
        services: [],
        dependencies: []
      ),
      expectedSwift: expectedSwift,
      accessLevel: .public,
      server: true
    )
  }

  private func assertIDLToStructuredSwiftTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String,
    accessLevel: CodeGenerator.Config.AccessLevel,
    server: Bool = false,
    grpcCoreModuleName: String = "GRPCCore"
  ) throws {
    let translator = IDLToStructuredSwiftTranslator()
    let structuredSwift = try translator.translate(
      codeGenerationRequest: codeGenerationRequest,
      accessLevel: accessLevel,
      accessLevelOnImports: true,
      client: false,
      server: server,
      grpcCoreModuleName: grpcCoreModuleName,
      availability: .macOS15Aligned
    )
    let renderer = TextBasedRenderer.default
    let sourceFile = try renderer.render(structured: structuredSwift)
    let contents = sourceFile.contents
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }

  func testSameNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "AService",
        typeName: "AService",
        propertyName: "aService"
      ),
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services must have unique descriptors. \
            AService is the descriptor of at least two different services.
            """
        )
      )
    }
  }

  func testSameDescriptorsServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "AService",
        typeName: "AService",
        propertyName: "aService"
      ),
      methods: []
    )

    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: ServiceName(
        identifyingName: "AService",
        typeName: "AService",
        propertyName: "aService"
      ),
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services must have unique descriptors. AService is the descriptor of at least two different services.
            """
        )
      )
    }
  }
  func testSameDescriptorsSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "namespacea.AService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_aService"
      ),
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services must have unique descriptors. \
            namespacea.AService is the descriptor of at least two different services.
            """
        )
      )
    }
  }

  func testSameGeneratedNameServicesSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "/// Documentation for AService\n",
      name: ServiceName(
        identifyingName: "namespacea.AService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_aService"
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "/// Documentation for BService\n",
      name: ServiceName(
        identifyingName: "namespacea.BService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_aService"
      ),
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .internal,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) { error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            There must be a unique (namespace, service_name) pair for each service. \
            NamespaceA_AService is used as a <namespace>_<service_name> construction for multiple services.
            """
        )
      )
    }
  }

  func testSameBaseNameMethodsSameServiceError() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: MethodName(identifyingName: "MethodA", typeName: "MethodA", functionName: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "namespacea.AService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_aService"
      ),
      methods: [methodA, methodA]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) { error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique base names. \
            MethodA is used as a base name for multiple methods of the namespacea.AService service.
            """
        )
      )
    }
  }

  func testSameGeneratedUpperCaseNameMethodsSameServiceError() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: MethodName(
        identifyingName: "MethodA",
        typeName: "MethodA",
        functionName: "methodA"
      ),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: MethodName(
        identifyingName: "MethodB",
        typeName: "MethodA",
        functionName: "methodA"
      ),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "namespacea.AService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_AService"
      ),
      methods: [methodA, methodB]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) { error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique generated upper case names. \
            MethodA is used as a generated upper case name for multiple methods of the \
            namespacea.AService service.
            """
        )
      )
    }
  }

  func testSameLowerCaseNameMethodsSameServiceError() throws {
    let methodA = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: MethodName(identifyingName: "MethodA", typeName: "MethodA", functionName: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let methodB = MethodDescriptor(
      documentation: "Documentation for MethodA",
      name: MethodName(identifyingName: "MethodB", typeName: "MethodB", functionName: "methodA"),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: ServiceName(
        identifyingName: "namespacea.AService",
        typeName: "NamespaceA_AService",
        propertyName: "namespacea_aService"
      ),
      methods: [methodA, methodB]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique lower case names. \
            methodA is used as a signature name for multiple methods of the \
            namespacea.AService service.
            """
        )
      )
    }
  }

  func testSameGeneratedNameNoNamespaceServiceAndNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: ServiceName(
        identifyingName: "SameName",
        typeName: "SameName_BService",
        propertyName: "sameName"
      ),
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: ServiceName(
        identifyingName: "sameName.BService",
        typeName: "SameName_BService",
        propertyName: "sameName"
      ),
      methods: []
    )
    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        accessLevel: .public,
        accessLevelOnImports: true,
        client: true,
        server: true,
        grpcCoreModuleName: "GRPCCore",
        availability: .macOS15Aligned
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            There must be a unique (namespace, service_name) pair for each service. \
            SameName_BService is used as a <namespace>_<service_name> construction for multiple services.
            """
        )
      )
    }
  }
}

#endif  // os(macOS) || os(Linux)
