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

import Testing

@testable import GRPCCodeGen

extension StructuedSwiftTests {
  @Suite("Metadata")
  struct Metadata {
    @Test("typealias Input = <Name>", arguments: AccessModifier.allCases)
    func methodInputTypealias(access: AccessModifier) {
      let decl: TypealiasDescription = .methodInput(accessModifier: access, name: "Foo")
      let expected = "\(access) typealias Input = Foo"
      #expect(render(.typealias(decl)) == expected)
    }

    @Test("typealias Output = <Name>", arguments: AccessModifier.allCases)
    func methodOutputTypealias(access: AccessModifier) {
      let decl: TypealiasDescription = .methodOutput(accessModifier: access, name: "Foo")
      let expected = "\(access) typealias Output = Foo"
      #expect(render(.typealias(decl)) == expected)
    }

    @Test(
      "static let descriptor = GRPCCore.MethodDescriptor(...)",
      arguments: AccessModifier.allCases
    )
    func staticMethodDescriptorProperty(access: AccessModifier) {
      let decl: VariableDescription = .methodDescriptor(
        accessModifier: access,
        literalFullyQualifiedService: "foo.Foo",
        literalMethodName: "Bar"
      )

      let expected = """
        \(access) static let descriptor = GRPCCore.MethodDescriptor(
          service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "foo.Foo"),
          method: "Bar"
        )
        """
      #expect(render(.variable(decl)) == expected)
    }

    @Test(
      "static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService:)",
      arguments: AccessModifier.allCases
    )
    func staticServiceDescriptorProperty(access: AccessModifier) {
      let decl: VariableDescription = .serviceDescriptor(
        accessModifier: access,
        literalFullyQualifiedService: "foo.Bar"
      )

      let expected = """
        \(access) static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "foo.Bar")
        """
      #expect(render(.variable(decl)) == expected)
    }

    @Test("extension GRPCCore.ServiceDescriptor { ... }", arguments: AccessModifier.allCases)
    func staticServiceDescriptorPropertyExtension(access: AccessModifier) {
      let decl: ExtensionDescription = .serviceDescriptor(
        accessModifier: access,
        propertyName: "foo",
        literalFullyQualifiedService: "echo.EchoService"
      )

      let expected = """
        extension GRPCCore.ServiceDescriptor {
          /// Service descriptor for the "echo.EchoService" service.
          \(access) static let foo = GRPCCore.ServiceDescriptor(fullyQualifiedService: "echo.EchoService")
        }
        """
      #expect(render(.extension(decl)) == expected)
    }

    @Test(
      "static let descriptors: [GRPCCore.MethodDescriptor] = [...]",
      arguments: AccessModifier.allCases
    )
    func staticMethodDescriptorsArray(access: AccessModifier) {
      let decl: VariableDescription = .methodDescriptorsArray(
        accessModifier: access,
        methodNamespaceNames: ["Foo", "Bar", "Baz"]
      )

      let expected = """
        \(access) static let descriptors: [GRPCCore.MethodDescriptor] = [
          Foo.descriptor,
          Bar.descriptor,
          Baz.descriptor
        ]
        """
      #expect(render(.variable(decl)) == expected)
    }

    @Test("enum <Method> { ... }", arguments: AccessModifier.allCases)
    func methodNamespaceEnum(access: AccessModifier) {
      let decl: EnumDescription = .methodNamespace(
        accessModifier: access,
        name: "Foo",
        literalMethod: "Foo",
        literalFullyQualifiedService: "bar.Bar",
        inputType: "FooInput",
        outputType: "FooOutput"
      )

      let expected = """
        \(access) enum Foo {
          /// Request type for "Foo".
          \(access) typealias Input = FooInput
          /// Response type for "Foo".
          \(access) typealias Output = FooOutput
          /// Descriptor for "Foo".
          \(access) static let descriptor = GRPCCore.MethodDescriptor(
            service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "bar.Bar"),
            method: "Foo"
          )
        }
        """
      #expect(render(.enum(decl)) == expected)
    }

    @Test("enum Method { ... }", arguments: AccessModifier.allCases)
    func methodsNamespaceEnum(access: AccessModifier) {
      let decl: EnumDescription = .methodsNamespace(
        accessModifier: access,
        literalFullyQualifiedService: "bar.Bar",
        methods: [
          .init(
            documentation: "",
            name: .init(base: "Foo", generatedUpperCase: "Foo", generatedLowerCase: "foo"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "FooInput",
            outputType: "FooOutput"
          )
        ]
      )

      let expected = """
        \(access) enum Method {
          /// Namespace for "Foo" metadata.
          \(access) enum Foo {
            /// Request type for "Foo".
            \(access) typealias Input = FooInput
            /// Response type for "Foo".
            \(access) typealias Output = FooOutput
            /// Descriptor for "Foo".
            \(access) static let descriptor = GRPCCore.MethodDescriptor(
              service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "bar.Bar"),
              method: "Foo"
            )
          }
          /// Descriptors for all methods in the "bar.Bar" service.
          \(access) static let descriptors: [GRPCCore.MethodDescriptor] = [
            Foo.descriptor
          ]
        }
        """
      #expect(render(.enum(decl)) == expected)
    }

    @Test("enum Method { ... } (no methods)", arguments: AccessModifier.allCases)
    func methodsNamespaceEnumNoMethods(access: AccessModifier) {
      let decl: EnumDescription = .methodsNamespace(
        accessModifier: access,
        literalFullyQualifiedService: "bar.Bar",
        methods: []
      )

      let expected = """
        \(access) enum Method {
          /// Descriptors for all methods in the "bar.Bar" service.
          \(access) static let descriptors: [GRPCCore.MethodDescriptor] = []
        }
        """
      #expect(render(.enum(decl)) == expected)
    }

    @Test("enum <Service> { ... }", arguments: AccessModifier.allCases)
    func serviceNamespaceEnum(access: AccessModifier) {
      let decl: EnumDescription = .serviceNamespace(
        accessModifier: access,
        name: "Foo",
        literalFullyQualifiedService: "Foo",
        methods: [
          .init(
            documentation: "",
            name: .init(base: "Bar", generatedUpperCase: "Bar", generatedLowerCase: "bar"),
            isInputStreaming: false,
            isOutputStreaming: false,
            inputType: "BarInput",
            outputType: "BarOutput"
          )
        ]
      )

      let expected = """
        \(access) enum Foo {
          /// Service descriptor for the "Foo" service.
          \(access) static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "Foo")
          /// Namespace for method metadata.
          \(access) enum Method {
            /// Namespace for "Bar" metadata.
            \(access) enum Bar {
              /// Request type for "Bar".
              \(access) typealias Input = BarInput
              /// Response type for "Bar".
              \(access) typealias Output = BarOutput
              /// Descriptor for "Bar".
              \(access) static let descriptor = GRPCCore.MethodDescriptor(
                service: GRPCCore.ServiceDescriptor(fullyQualifiedService: "Foo"),
                method: "Bar"
              )
            }
            /// Descriptors for all methods in the "Foo" service.
            \(access) static let descriptors: [GRPCCore.MethodDescriptor] = [
              Bar.descriptor
            ]
          }
        }
        """
      #expect(render(.enum(decl)) == expected)
    }

    @Test("enum <Service> { ... } (no methods)", arguments: AccessModifier.allCases)
    func serviceNamespaceEnumNoMethods(access: AccessModifier) {
      let decl: EnumDescription = .serviceNamespace(
        accessModifier: access,
        name: "Foo",
        literalFullyQualifiedService: "Foo",
        methods: []
      )

      let expected = """
        \(access) enum Foo {
          /// Service descriptor for the "Foo" service.
          \(access) static let descriptor = GRPCCore.ServiceDescriptor(fullyQualifiedService: "Foo")
          /// Namespace for method metadata.
          \(access) enum Method {
            /// Descriptors for all methods in the "Foo" service.
            \(access) static let descriptors: [GRPCCore.MethodDescriptor] = []
          }
        }
        """

      #expect(render(.enum(decl)) == expected)
    }
  }
}
