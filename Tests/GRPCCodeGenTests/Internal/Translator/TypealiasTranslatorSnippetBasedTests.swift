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

import Testing

@testable import GRPCCodeGen

@Suite
struct TypealiasTranslatorSnippetBasedTests {
  @Test
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

    let expectedSwift = """
      /// Namespace containing generated types for the "namespaceA.ServiceA" service.
      public enum NamespaceA_ServiceA {
          /// Service descriptor for the "namespaceA.ServiceA" service.
          public static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "namespaceA.ServiceA")
          /// Namespace for method metadata.
          public enum Method {
              /// Namespace for "MethodA" metadata.
              public enum MethodA {
                  /// Request type for "MethodA".
                  public typealias Input = NamespaceA_ServiceARequest
                  /// Response type for "MethodA".
                  public typealias Output = NamespaceA_ServiceAResponse
                  /// Descriptor for "MethodA".
                  public static let descriptor = GRPCCore.MethodDescriptor(
                      service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "namespaceA.ServiceA"),
                      method: "MethodA"
                  )
              }
              /// Descriptors for all methods in the "namespaceA.ServiceA" service.
              public static let descriptors: [GRPCCore.MethodDescriptor] = [
                  MethodA.descriptor
              ]
          }
      }
      extension GRPCCore.ServiceDescriptor {
          /// Service descriptor for the "namespaceA.ServiceA" service.
          public static let namespaceA_ServiceA = GRPCCore.ServiceDescriptor(fullyQualifiedService: "namespaceA.ServiceA")
      }
      """

    #expect(self.render(accessLevel: .public, service: service) == expectedSwift)
  }
}

extension TypealiasTranslatorSnippetBasedTests {
  func render(
    accessLevel: SourceGenerator.Config.AccessLevel,
    service: ServiceDescriptor
  ) -> String {
    let translator = MetadataTranslator()
    let codeBlocks = translator.translate(
      accessModifier: AccessModifier(accessLevel),
      service: service
    )

    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    return renderer.renderedContents()
  }
}
