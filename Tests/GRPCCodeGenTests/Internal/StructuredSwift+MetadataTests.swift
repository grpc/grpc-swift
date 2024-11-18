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
    @Test("@available(...)")
    func grpcAvailability() async throws {
      let availability: AvailabilityDescription = .grpc
      let structDecl = StructDescription(name: "Ignored")
      let expected = """
        @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
        struct Ignored {}
        """

      #expect(render(.guarded(availability, .struct(structDecl))) == expected)
    }

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
        serviceNamespace: "FooService",
        literalMethodName: "Bar"
      )

      let expected = """
        \(access) static let descriptor = GRPCCore.MethodDescriptor(
          service: FooService.descriptor.fullyQualifiedService,
          method: "Bar"
        )
        """
      #expect(render(.variable(decl)) == expected)
    }

    @Test(
      "static let descriptor = GRPCCore.ServiceDescriptor.<Name>",
      arguments: AccessModifier.allCases
    )
    func staticServiceDescriptorProperty(access: AccessModifier) {
      let decl: VariableDescription = .serviceDescriptor(
        accessModifier: access,
        namespacedProperty: "foo"
      )

      let expected = "\(access) static let descriptor = GRPCCore.ServiceDescriptor.foo"
      #expect(render(.variable(decl)) == expected)
    }

    @Test("extension GRPCCore.ServiceDescriptor { ... }", arguments: AccessModifier.allCases)
    func staticServiceDescriptorPropertyExtension(access: AccessModifier) {
      let decl: ExtensionDescription = .serviceDescriptor(
        accessModifier: access,
        propertyName: "foo",
        literalNamespace: "echo",
        literalService: "EchoService"
      )

      let expected = """
        extension GRPCCore.ServiceDescriptor {
          \(access) static let foo = Self(
            package: "echo",
            service: "EchoService"
          )
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
        serviceNamespace: "Bar_Baz",
        inputType: "FooInput",
        outputType: "FooOutput"
      )

      let expected = """
        \(access) enum Foo {
          \(access) typealias Input = FooInput
          \(access) typealias Output = FooOutput
          \(access) static let descriptor = GRPCCore.MethodDescriptor(
            service: Bar_Baz.descriptor.fullyQualifiedService,
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
        serviceNamespace: "Bar_Baz",
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
          \(access) enum Foo {
            \(access) typealias Input = FooInput
            \(access) typealias Output = FooOutput
            \(access) static let descriptor = GRPCCore.MethodDescriptor(
              service: Bar_Baz.descriptor.fullyQualifiedService,
              method: "Foo"
            )
          }
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
        serviceNamespace: "Bar_Baz",
        methods: []
      )

      let expected = """
        \(access) enum Method {
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
        serviceDescriptorProperty: "foo",
        client: false,
        server: false,
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
          \(access) static let descriptor = GRPCCore.ServiceDescriptor.foo
          \(access) enum Method {
            \(access) enum Bar {
              \(access) typealias Input = BarInput
              \(access) typealias Output = BarOutput
              \(access) static let descriptor = GRPCCore.MethodDescriptor(
                service: Foo.descriptor.fullyQualifiedService,
                method: "Bar"
              )
            }
            \(access) static let descriptors: [GRPCCore.MethodDescriptor] = [
              Bar.descriptor
            ]
          }
        }
        """
      #expect(render(.enum(decl)) == expected)
    }

    @Test(
      "enum <Service> { ... } (no methods)",
      arguments: AccessModifier.allCases,
      [(true, true), (false, false), (true, false), (false, true)]
    )
    func serviceNamespaceEnumNoMethods(access: AccessModifier, config: (client: Bool, server: Bool))
    {
      let decl: EnumDescription = .serviceNamespace(
        accessModifier: access,
        name: "Foo",
        serviceDescriptorProperty: "foo",
        client: config.client,
        server: config.server,
        methods: []
      )

      var expected = """
        \(access) enum Foo {
          \(access) static let descriptor = GRPCCore.ServiceDescriptor.foo
          \(access) enum Method {
            \(access) static let descriptors: [GRPCCore.MethodDescriptor] = []
          }\n
        """

      if config.server {
        expected += """
            @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
            \(access) typealias StreamingServiceProtocol = Foo_StreamingServiceProtocol
            @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
            \(access) typealias ServiceProtocol = Foo_ServiceProtocol
          """
      }

      if config.client {
        if config.server {
          expected += "\n"
        }

        expected += """
            @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
            \(access) typealias ClientProtocol = Foo_ClientProtocol
            @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
            \(access) typealias Client = Foo_Client
          """
      }

      if config.client || config.server {
        expected += "\n}"
      } else {
        expected += "}"
      }

      #expect(render(.enum(decl)) == expected)
    }
  }
}
