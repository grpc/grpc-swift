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

  func testSameNameServicesNoNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "",
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

  func testSameNameServicesSameNamespaceError() throws {
    let serviceA = ServiceDescriptor(
      documentation: "Documentation for AService",
      name: "AService",
      namespace: "namespacea",
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

  func testSameNameMethodsSameServiceError() throws {
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

  func testSameNameNoNamespaceServiceAndNamespaceError() throws {
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
            Services with no namespace must not have the same names as the namespaces. \
            SameName is used as a name for a service with no namespace and a namespace.
            """
        )
      )
    }
  }
}

#endif  // os(macOS) || os(Linux)
