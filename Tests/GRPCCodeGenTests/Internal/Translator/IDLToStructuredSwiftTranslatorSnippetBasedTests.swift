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

final class IDLToStructuredSwiftTranslatorSnippetBasedTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo"))
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .typealias, name: "Bar"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .struct, name: "Baz"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .class, name: "Bac"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .enum, name: "Bap"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .protocol, name: "Bat"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .let, name: "Baq"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .var, name: "Bag"), module: "Foo")
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(item: .init(kind: .func, name: "Bak"), module: "Foo")
    )

    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      import Foo
      import typealias Foo.Bar
      import struct Foo.Baz
      import class Foo.Bac
      import enum Foo.Bap
      import protocol Foo.Bat
      import let Foo.Baq
      import var Foo.Bag
      import func Foo.Bak
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  func testPreconcurrencyImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo", preconcurrency: .required))
    dependencies.append(
      CodeGenerationRequest.Dependency(
        item: .init(kind: .enum, name: "Bar"),
        module: "Foo",
        preconcurrency: .required
      )
    )
    dependencies.append(
      CodeGenerationRequest.Dependency(
        module: "Baz",
        preconcurrency: .requiredOnOS(["Deq", "Der"])
      )
    )
    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      @preconcurrency import Foo
      @preconcurrency import enum Foo.Bar
      #if os(Deq) || os(Der)
      @preconcurrency import Baz
      #else
      import Baz
      #endif
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  func testSPIImports() throws {
    var dependencies = [CodeGenerationRequest.Dependency]()
    dependencies.append(CodeGenerationRequest.Dependency(module: "Foo", spi: "Secret"))
    dependencies.append(
      CodeGenerationRequest.Dependency(
        item: .init(kind: .enum, name: "Bar"),
        module: "Foo",
        spi: "Secret"
      )
    )

    let expectedSwift =
      """
      /// Some really exciting license header 2023.
      import GRPCCore
      @_spi(Secret) import Foo
      @_spi(Secret) import enum Foo.Bar
      """
    try self.assertIDLToStructuredSwiftTranslation(
      codeGenerationRequest: makeCodeGenerationRequest(dependencies: dependencies),
      expectedSwift: expectedSwift
    )
  }

  private func assertIDLToStructuredSwiftTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = IDLToStructuredSwiftTranslator()
    let structuredSwift = try translator.translate(
      codeGenerationRequest: codeGenerationRequest,
      client: false,
      server: false
    )
    let renderer = TextBasedRenderer.default
    let sourceFile = try renderer.render(structured: structuredSwift)
    let contents = sourceFile.contents
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }

  func testSameNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
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

  func testSameGeneratedNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )

    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      generatedName: "AService",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services in an empty namespace must have unique generated names. \
            AService is used as a name for multiple services without namespaces.
            """
        )
      )
    }
  }
  func testSameNameServicesSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
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

  func testSameGeneratedNameServicesSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services within the same namespace must have unique generated names. \
            AService is used as a generated name for multiple services in the namespacea namespace.
            """
        )
      )
    }
  }

  func testSameNameMethodsSameServiceError() throws {
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
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: [methodA, methodA]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
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

  func testSameGeneratedNameMethodsSameServiceError() throws {
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
      documentation: "Documentation for MethodA",
      name: "MethodB",
      generatedName: "MethodA",
      signatureName: "methodB",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: [methodA, methodB]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique generated names. \
            MethodA is used as a generated name for multiple methods of the AService service.
            """
        )
      )
    }
  }

  func testSameSignatureNameMethodsSameServiceError() throws {
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
      documentation: "Documentation for MethodA",
      name: "MethodB",
      generatedName: "MethodB",
      signatureName: "methodA",
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "NamespaceA_ServiceARequest",
      outputType: "NamespaceA_ServiceAResponse"
    )
    let service = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      generatedName: "AService",
      namespace: "namespacea",
      generatedNamespace: "NamespaceA",
      methods: [methodA, methodB]
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [service])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueMethodName,
          message: """
            Methods of a service must have unique signature names. \
            methodA is used as a signature name for multiple methods of the AService service.
            """
        )
      )
    }
  }

  func testSameGeneratedNameNoNamespaceServiceAndNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "SameName",
      generatedName: "SameName",
      namespace: "",
      generatedNamespace: "",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for BService",
      name: "BService",
      generatedName: "BService",
      namespace: "SameName",
      generatedNamespace: "SameName",
      methods: []
    )
    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .nonUniqueServiceName,
          message: """
            Services with no namespace must not have the same generated names as the namespaces. \
            SameName is used as a generated name for a service with no namespace and a namespace.
            """
        )
      )
    }
  }

  func testEmptyNamespaceAndNonEmptyGeneratedNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "SameName",
      generatedName: "SameName",
      namespace: "",
      generatedNamespace: "NonEmpty",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .invalidGeneratedNamespace,
          message: """
            Services with an empty namespace must have an empty generated namespace. \
            SameName has an empty namespace, but a non-empty generated namespace.
            """
        )
      )
    }
  }

  func testNonEmptyNamespaceAndEmptyGeneratedNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "SameName",
      generatedName: "SameName",
      namespace: "NonEmpty",
      generatedNamespace: "",
      methods: []
    )

    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .invalidGeneratedNamespace,
          message: """
            Services with a non-empty namespace must have a non-empty generated namespace. \
            SameName has a non-empty namespace, but an empty generated namespace.
            """
        )
      )
    }
  }

  func testNamespaceAndGeneratedNamespaceServicesCoincide() throws {
    // Same namespaces, different generated namespaces.
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "ServiceA",
      generatedName: "ServiceA",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceA",
      methods: []
    )
    let serviceB = ServiceDescriptor(
      documentation: "Documentation for SameName service with no namespace",
      name: "ServiceB",
      generatedName: "ServiceB",
      namespace: "namespaceA",
      generatedNamespace: "NamespaceB",
      methods: []
    )
    let codeGenerationRequest = makeCodeGenerationRequest(services: [serviceA, serviceB])
    let translator = IDLToStructuredSwiftTranslator()
    XCTAssertThrowsError(
      ofType: CodeGenError.self,
      try translator.translate(
        codeGenerationRequest: codeGenerationRequest,
        client: true,
        server: true
      )
    ) {
      error in
      XCTAssertEqual(
        error as CodeGenError,
        CodeGenError(
          code: .invalidGeneratedNamespace,
          message: """
            All services within a namespace must have the same generated namespace. \
            ServiceB doesn't have the same generated namespace as other services \
            within the namespaceA namespace.
            """
        )
      )
    }
  }
}

#endif  // os(macOS) || os(Linux)
