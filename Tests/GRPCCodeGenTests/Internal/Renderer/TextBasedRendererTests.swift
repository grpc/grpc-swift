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
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import XCTest

@testable import GRPCCodeGen

final class Test_TextBasedRenderer: XCTestCase {

  func testComment() throws {
    try _test(
      .inline(
        #"""
        Generated by foo

        Also, bar
        """#
      ),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: #"""
        // Generated by foo
        //
        // Also, bar
        """#
    )
    try _test(
      .doc(
        #"""
        Generated by foo

        Also, bar
        """#
      ),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: #"""
        /// Generated by foo
        ///
        /// Also, bar
        """#
    )
    try _test(
      .mark("Lorem ipsum", sectionBreak: false),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: #"""
        // MARK: Lorem ipsum
        """#
    )
    try _test(
      .mark("Lorem ipsum", sectionBreak: true),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: #"""
        // MARK: - Lorem ipsum
        """#
    )
    try _test(
      .inline(
        """
        Generated by foo\r\nAlso, bar
        """
      ),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: #"""
        // Generated by foo
        // Also, bar
        """#
    )
    try _test(
      .preFormatted("/// Lorem ipsum\n"),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: """
        /// Lorem ipsum
        """
    )
    try _test(
      .preFormatted("/// Lorem ipsum\n\n/// Lorem ipsum\n"),
      renderedBy: { $0.renderComment(_:) },
      rendersAs: """
        /// Lorem ipsum

        /// Lorem ipsum
        """
    )
  }

  func testImports() throws {
    try _test(nil, renderedBy: { $0.renderImports(_:) }, rendersAs: "")
    try _test(
      [
        ImportDescription(moduleName: "Foo"),
        ImportDescription(moduleName: "Bar"),
        ImportDescription(accessLevel: .fileprivate, moduleName: "BazFileprivate"),
        ImportDescription(accessLevel: .private, moduleName: "BazPrivate"),
        ImportDescription(accessLevel: .internal, moduleName: "BazInternal"),
        ImportDescription(accessLevel: .package, moduleName: "BazPackage"),
        ImportDescription(accessLevel: .public, moduleName: "BazPublic"),
      ],
      renderedBy: { $0.renderImports(_:) },
      rendersAs: #"""
        import Foo
        import Bar
        fileprivate import BazFileprivate
        private import BazPrivate
        internal import BazInternal
        package import BazPackage
        public import BazPublic
        """#
    )
    try _test(
      [ImportDescription(moduleName: "Foo", spi: "Secret")],
      renderedBy: { $0.renderImports(_:) },
      rendersAs: #"""
        @_spi(Secret) import Foo
        """#
    )
    try _test(
      [
        ImportDescription(
          moduleName: "Foo",
          preconcurrency: .onOS(["Bar", "Baz"])
        )
      ],
      renderedBy: { $0.renderImports(_:) },
      rendersAs: #"""
        #if os(Bar) || os(Baz)
        @preconcurrency import Foo
        #else
        import Foo
        #endif
        """#
    )
    try _test(
      [
        ImportDescription(moduleName: "Foo", preconcurrency: .always),
        ImportDescription(
          moduleName: "Bar",
          spi: "Secret",
          preconcurrency: .always
        ),
      ],
      renderedBy: { $0.renderImports(_:) },
      rendersAs: #"""
        @preconcurrency import Foo
        @preconcurrency @_spi(Secret) import Bar
        """#
    )

    try _test(
      [
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .typealias, name: "Bar")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .struct, name: "Baz")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .class, name: "Bac")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .enum, name: "Bap")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .protocol, name: "Bat")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .let, name: "Bam")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .var, name: "Bag")
        ),
        ImportDescription(
          moduleName: "Foo",
          item: ImportDescription.Item(kind: .func, name: "Bak")
        ),
        ImportDescription(
          moduleName: "Foo",
          spi: "Secret",
          item: ImportDescription.Item(kind: .func, name: "SecretBar")
        ),
        ImportDescription(
          moduleName: "Foo",
          preconcurrency: .always,
          item: ImportDescription.Item(kind: .func, name: "PreconcurrencyBar")
        ),
      ],
      renderedBy: { $0.renderImports(_:) },
      rendersAs: #"""
        import typealias Foo.Bar
        import struct Foo.Baz
        import class Foo.Bac
        import enum Foo.Bap
        import protocol Foo.Bat
        import let Foo.Bam
        import var Foo.Bag
        import func Foo.Bak
        @_spi(Secret) import func Foo.SecretBar
        @preconcurrency import func Foo.PreconcurrencyBar
        """#
    )
  }

  func testAccessModifiers() throws {
    try _test(
      .public,
      renderedBy: { $0.renderedAccessModifier(_:) },
      rendersAs: #"""
        public
        """#
    )
    try _test(
      .internal,
      renderedBy: { $0.renderedAccessModifier(_:) },
      rendersAs: #"""
        internal
        """#
    )
    try _test(
      .fileprivate,
      renderedBy: { $0.renderedAccessModifier(_:) },
      rendersAs: #"""
        fileprivate
        """#
    )
    try _test(
      .private,
      renderedBy: { $0.renderedAccessModifier(_:) },
      rendersAs: #"""
        private
        """#
    )
  }

  func testLiterals() throws {
    try _test(
      .string("hi"),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        "hi"
        """#
    )
    try _test(
      .string("this string: \"foo\""),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        #"this string: "foo""#
        """#
    )
    try _test(
      .nil,
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        nil
        """#
    )
    try _test(
      .array([]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        []
        """#
    )
    try _test(
      .array([.literal(.nil)]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [
            nil
        ]
        """#
    )
    try _test(
      .array([.literal(.nil), .literal(.nil)]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [
            nil,
            nil
        ]
        """#
    )
    try _test(
      .dictionary([]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [:]
        """#
    )
    try _test(
      .dictionary([.init(key: .literal("foo"), value: .literal("bar"))]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [
            "foo": "bar"
        ]
        """#
    )
    try _test(
      .dictionary([
        .init(key: .literal("foo"), value: .literal("bar")),
        .init(key: .literal("bar"), value: .literal("baz")),
      ]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [
            "foo": "bar",
            "bar": "baz"
        ]
        """#
    )
  }

  func testExpression() throws {
    try _test(
      .literal(.nil),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        nil
        """#
    )
    try _test(
      .identifierPattern("foo"),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        foo
        """#
    )
    try _test(
      .memberAccess(.init(left: .identifierPattern("foo"), right: "bar")),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        foo.bar
        """#
    )
    try _test(
      .functionCall(
        .init(
          calledExpression: .identifierPattern("callee"),
          arguments: [.init(label: nil, expression: .identifierPattern("foo"))]
        )
      ),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        callee(foo)
        """#
    )
  }

  func testDeclaration() throws {
    try _test(
      .variable(kind: .let, left: "foo"),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        let foo
        """#
    )
    try _test(
      .extension(.init(onType: "String", declarations: [])),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        extension String {
        }
        """#
    )
    try _test(
      .struct(.init(name: "Foo")),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        struct Foo {}
        """#
    )
    try _test(
      .protocol(.init(name: "Foo")),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        protocol Foo {}
        """#
    )
    try _test(
      .enum(.init(name: "Foo")),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        enum Foo {}
        """#
    )
    try _test(
      .typealias(.init(name: "foo", existingType: .member(["Foo", "Bar"]))),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        typealias foo = Foo.Bar
        """#
    )
    try _test(
      .function(FunctionDescription.init(kind: .function(name: "foo"), body: [])),
      renderedBy: { $0.renderDeclaration(_:) },
      rendersAs: #"""
        func foo() {}
        """#
    )
  }

  func testFunctionKind() throws {
    try _test(
      .initializer,
      renderedBy: { $0.renderedFunctionKind(_:) },
      rendersAs: #"""
        init
        """#
    )
    try _test(
      .function(name: "funky"),
      renderedBy: { $0.renderedFunctionKind(_:) },
      rendersAs: #"""
        func funky
        """#
    )
    try _test(
      .function(name: "funky", isStatic: true),
      renderedBy: { $0.renderedFunctionKind(_:) },
      rendersAs: #"""
        static func funky
        """#
    )
  }

  func testFunctionKeyword() throws {
    try _test(
      .throws,
      renderedBy: { $0.renderedFunctionKeyword(_:) },
      rendersAs: #"""
        throws
        """#
    )
    try _test(
      .async,
      renderedBy: { $0.renderedFunctionKeyword(_:) },
      rendersAs: #"""
        async
        """#
    )
  }

  func testParameter() throws {
    try _test(
      .init(label: "l", name: "n", type: .member("T"), defaultValue: .literal(.nil)),
      renderedBy: { $0.renderParameter(_:) },
      rendersAs: #"""
        l n: T = nil
        """#
    )
    try _test(
      .init(label: nil, name: "n", type: .member("T"), defaultValue: .literal(.nil)),
      renderedBy: { $0.renderParameter(_:) },
      rendersAs: #"""
        _ n: T = nil
        """#
    )
    try _test(
      .init(label: "l", name: nil, type: .member("T"), defaultValue: .literal(.nil)),
      renderedBy: { $0.renderParameter(_:) },
      rendersAs: #"""
        l: T = nil
        """#
    )
    try _test(
      .init(label: nil, name: nil, type: .member("T"), defaultValue: .literal(.nil)),
      renderedBy: { $0.renderParameter(_:) },
      rendersAs: #"""
        _: T = nil
        """#
    )
    try _test(
      .init(label: nil, name: nil, type: .member("T"), defaultValue: nil),
      renderedBy: { $0.renderParameter(_:) },
      rendersAs: #"""
        _: T
        """#
    )
  }

  func testGenericFunction() throws {
    try _test(
      .init(
        accessModifier: .public,
        kind: .function(name: "f"),
        generics: [.member("R")],
        parameters: [],
        whereClause: WhereClause(requirements: [.conformance("R", "Sendable")]),
        body: []
      ),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        public func f<R>() where R: Sendable {}
        """#
    )
    try _test(
      .init(
        accessModifier: .public,
        kind: .function(name: "f"),
        generics: [.member("R"), .member("T")],
        parameters: [],
        whereClause: WhereClause(requirements: [
          .conformance("R", "Sendable"), .conformance("T", "Encodable"),
        ]),
        body: []
      ),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        public func f<R, T>() where R: Sendable, T: Encodable {}
        """#
    )
  }

  func testFunction() throws {
    try _test(
      .init(accessModifier: .public, kind: .function(name: "f"), parameters: [], body: []),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        public func f() {}
        """#
    )
    try _test(
      .init(
        accessModifier: .public,
        kind: .function(name: "f"),
        parameters: [.init(label: "a", name: "b", type: .member("C"), defaultValue: nil)],
        body: []
      ),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        public func f(a b: C) {}
        """#
    )
    try _test(
      .init(
        accessModifier: .public,
        kind: .function(name: "f"),
        parameters: [
          .init(label: "a", name: "b", type: .member("C"), defaultValue: nil),
          .init(label: nil, name: "d", type: .member("E"), defaultValue: .literal(.string("f"))),
        ],
        body: []
      ),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        public func f(
            a b: C,
            _ d: E = "f"
        ) {}
        """#
    )
    try _test(
      .init(
        kind: .function(name: "f"),
        parameters: [],
        keywords: [.async, .throws],
        returnType: .identifierType(TypeName.string)
      ),
      renderedBy: { $0.renderFunction(_:) },
      rendersAs: #"""
        func f() async throws -> Swift.String
        """#
    )
  }

  func testIdentifiers() throws {
    try _test(
      .pattern("foo"),
      renderedBy: { $0.renderIdentifier(_:) },
      rendersAs: #"""
        foo
        """#
    )
  }

  func testMemberAccess() throws {
    try _test(
      .init(left: .identifierPattern("foo"), right: "bar"),
      renderedBy: { $0.renderMemberAccess(_:) },
      rendersAs: #"""
        foo.bar
        """#
    )
    try _test(
      .init(left: nil, right: "bar"),
      renderedBy: { $0.renderMemberAccess(_:) },
      rendersAs: #"""
        .bar
        """#
    )
  }

  func testFunctionCallArgument() throws {
    try _test(
      .init(label: "foo", expression: .identifierPattern("bar")),
      renderedBy: { $0.renderFunctionCallArgument(_:) },
      rendersAs: #"""
        foo: bar
        """#
    )
    try _test(
      .init(label: nil, expression: .identifierPattern("bar")),
      renderedBy: { $0.renderFunctionCallArgument(_:) },
      rendersAs: #"""
        bar
        """#
    )
  }

  func testFunctionCall() throws {
    try _test(
      .functionCall(.init(calledExpression: .identifierPattern("callee"))),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        callee()
        """#
    )
    try _test(
      .functionCall(
        .init(
          calledExpression: .identifierPattern("callee"),
          arguments: [.init(label: "foo", expression: .identifierPattern("bar"))]
        )
      ),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        callee(foo: bar)
        """#
    )
    try _test(
      .functionCall(
        .init(
          calledExpression: .identifierPattern("callee"),
          arguments: [
            .init(label: "foo", expression: .identifierPattern("bar")),
            .init(label: "baz", expression: .identifierPattern("boo")),
          ]
        )
      ),
      renderedBy: { $0.renderExpression(_:) },
      rendersAs: #"""
        callee(
            foo: bar,
            baz: boo
        )
        """#
    )
  }

  func testExtension() throws {
    try _test(
      .init(
        accessModifier: .public,
        onType: "Info",
        declarations: [.variable(kind: .let, left: "foo", type: .member("Int"))]
      ),
      renderedBy: { $0.renderExtension(_:) },
      rendersAs: #"""
        public extension Info {
            let foo: Int
        }
        """#
    )
  }

  func testDeprecation() throws {
    try _test(
      .init(),
      renderedBy: { $0.renderDeprecation(_:) },
      rendersAs: #"""
        @available(*, deprecated)
        """#
    )
    try _test(
      .init(message: "some message"),
      renderedBy: { $0.renderDeprecation(_:) },
      rendersAs: #"""
        @available(*, deprecated, message: "some message")
        """#
    )
    try _test(
      .init(renamed: "newSymbol(param:)"),
      renderedBy: { $0.renderDeprecation(_:) },
      rendersAs: #"""
        @available(*, deprecated, renamed: "newSymbol(param:)")
        """#
    )
    try _test(
      .init(message: "some message", renamed: "newSymbol(param:)"),
      renderedBy: { $0.renderDeprecation(_:) },
      rendersAs: #"""
        @available(*, deprecated, message: "some message", renamed: "newSymbol(param:)")
        """#
    )
  }

  func testAvailability() throws {
    try _test(
      .init(osVersions: [
        .init(os: .macOS, version: "12.0"),
        .init(os: .iOS, version: "13.1.2"),
        .init(os: .watchOS, version: "8.1.2"),
        .init(os: .tvOS, version: "15.0.2"),
      ]),
      renderedBy: { $0.renderAvailability(_:) },
      rendersAs: #"""
        @available(macOS 12.0, iOS 13.1.2, watchOS 8.1.2, tvOS 15.0.2, *)
        """#
    )
  }

  func testBindingKind() throws {
    try _test(
      .var,
      renderedBy: { $0.renderedBindingKind(_:) },
      rendersAs: #"""
        var
        """#
    )
    try _test(
      .let,
      renderedBy: { $0.renderedBindingKind(_:) },
      rendersAs: #"""
        let
        """#
    )
  }

  func testVariable() throws {
    try _test(
      .init(
        accessModifier: .public,
        isStatic: true,
        kind: .let,
        left: .identifierPattern("foo"),
        type: .init(TypeName.string),
        right: .literal(.string("bar"))
      ),
      renderedBy: { $0.renderVariable(_:) },
      rendersAs: #"""
        public static let foo: Swift.String = "bar"
        """#
    )
    try _test(
      .init(
        accessModifier: .internal,
        isStatic: false,
        kind: .var,
        left: .identifierPattern("foo"),
        type: nil,
        right: nil
      ),
      renderedBy: { $0.renderVariable(_:) },
      rendersAs: #"""
        internal var foo
        """#
    )
    try _test(
      .init(
        kind: .var,
        left: .identifierPattern("foo"),
        type: .init(TypeName.int),
        getter: [CodeBlock.expression(.literal(.int(42)))]
      ),
      renderedBy: { $0.renderVariable(_:) },
      rendersAs: #"""
        var foo: Swift.Int {
            42
        }
        """#
    )
    try _test(
      .init(
        kind: .var,
        left: .identifierPattern("foo"),
        type: .init(TypeName.int),
        getter: [CodeBlock.expression(.literal(.int(42)))],
        getterEffects: [.throws]
      ),
      renderedBy: { $0.renderVariable(_:) },
      rendersAs: #"""
        var foo: Swift.Int {
            get throws {
                42
            }
        }
        """#
    )
  }

  func testStruct() throws {
    try _test(
      StructDescription(name: "Structy"),
      renderedBy: { $0.renderStruct(_:) },
      rendersAs: #"""
        struct Structy {}
        """#
    )
    try _test(
      StructDescription(
        name: "Structy",
        conformances: ["Foo"]
      ),
      renderedBy: { $0.renderStruct(_:) },
      rendersAs: #"""
        struct Structy: Foo {}
        """#
    )
    try _test(
      StructDescription(
        name: "Structy",
        generics: [.member("T")],
      ),
      renderedBy: { $0.renderStruct(_:) },
      rendersAs: #"""
        struct Structy<T> {}
        """#
    )
    try _test(
      StructDescription(
        name: "Structy",
        generics: [.member("T")],
        whereClause: WhereClause(requirements: [.conformance("T", "Foo")])
      ),
      renderedBy: { $0.renderStruct(_:) },
      rendersAs: #"""
        struct Structy<T> where T: Foo {}
        """#
    )
    try _test(
      StructDescription(
        name: "Structy",
        generics: [.member("T")],
        conformances: ["Hashable"],
        whereClause: WhereClause(requirements: [.conformance("T", "Foo")])
      ),
      renderedBy: { $0.renderStruct(_:) },
      rendersAs: #"""
        struct Structy<T>: Hashable where T: Foo {}
        """#
    )
  }

  func testProtocol() throws {
    try _test(
      .init(name: "Protocoly"),
      renderedBy: { $0.renderProtocol(_:) },
      rendersAs: #"""
        protocol Protocoly {}
        """#
    )
  }

  func testEnum() throws {
    try _test(
      .init(name: "Enumy"),
      renderedBy: { $0.renderEnum(_:) },
      rendersAs: #"""
        enum Enumy {}
        """#
    )
  }

  func testCodeBlockItem() throws {
    try _test(
      .declaration(.variable(kind: .let, left: "foo")),
      renderedBy: { $0.renderCodeBlockItem(_:) },
      rendersAs: #"""
        let foo
        """#
    )
    try _test(
      .expression(.literal(.nil)),
      renderedBy: { $0.renderCodeBlockItem(_:) },
      rendersAs: #"""
        nil
        """#
    )
  }

  func testCodeBlock() throws {
    try _test(
      .init(
        comment: .inline("- MARK: Section"),
        item: .declaration(.variable(kind: .let, left: "foo"))
      ),
      renderedBy: { $0.renderCodeBlock(_:) },
      rendersAs: #"""
        // - MARK: Section
        let foo
        """#
    )
    try _test(
      .init(comment: nil, item: .declaration(.variable(kind: .let, left: "foo"))),
      renderedBy: { $0.renderCodeBlock(_:) },
      rendersAs: #"""
        let foo
        """#
    )
  }

  func testTypealias() throws {
    try _test(
      .init(name: "inty", existingType: .member("Int")),
      renderedBy: { $0.renderTypealias(_:) },
      rendersAs: #"""
        typealias inty = Int
        """#
    )
    try _test(
      .init(accessModifier: .private, name: "inty", existingType: .member("Int")),
      renderedBy: { $0.renderTypealias(_:) },
      rendersAs: #"""
        private typealias inty = Int
        """#
    )
  }

  func testFile() throws {
    try _test(
      .init(
        topComment: .inline("hi"),
        imports: [.init(moduleName: "Foo")],
        codeBlocks: [.init(comment: nil, item: .declaration(.struct(.init(name: "Bar"))))]
      ),
      renderedBy: { $0.renderFile(_:) },
      rendersAs: #"""
        // hi

        import Foo

        struct Bar {}
        """#
    )
  }

  func testIndentation() throws {
    try _test(
      .init(
        topComment: .inline("hi"),
        imports: [.init(moduleName: "Foo")],
        codeBlocks: [
          .init(
            comment: nil,
            item: .declaration(.struct(.init(name: "Bar", members: [.struct(.init(name: "Baz"))])))
          )
        ]
      ),
      renderedBy: { $0.renderFile(_:) },
      rendersAs: #"""
        // hi

        import Foo

        struct Bar {
          struct Baz {}
        }
        """#,
      indentation: 2
    )

    try _test(
      .array([.literal(.nil), .literal(.nil)]),
      renderedBy: { $0.renderLiteral(_:) },
      rendersAs: #"""
        [
           nil,
           nil
        ]
        """#,
      indentation: 3
    )

    try _test(
      .init(
        kind: .var,
        left: .identifierPattern("foo"),
        type: .init(TypeName.int),
        getter: [CodeBlock.expression(.literal(.int(42)))],
        getterEffects: [.throws]
      ),
      renderedBy: { $0.renderVariable(_:) },
      rendersAs: #"""
        var foo: Swift.Int {
             get throws {
                  42
             }
        }
        """#,
      indentation: 5
    )
  }
}

extension Test_TextBasedRenderer {
  func _test<Input>(
    _ input: Input,
    renderedBy renderClosure: (TextBasedRenderer) -> ((Input) -> String),
    rendersAs output: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    indentation: Int = 4
  ) throws {
    let renderer = TextBasedRenderer(indentation: indentation)
    XCTAssertEqual(renderClosure(renderer)(input), output, file: file, line: line)
  }

  func _test<Input>(
    _ input: Input,
    renderedBy renderClosure: (TextBasedRenderer) -> ((Input) -> Void),
    rendersAs output: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    indentation: Int = 4
  ) throws {
    try _test(
      input,
      renderedBy: { renderer in
        let closure = renderClosure(renderer)
        return { input in
          closure(input)
          return renderer.renderedContents()
        }
      },
      rendersAs: output,
      indentation: indentation
    )
  }
}
